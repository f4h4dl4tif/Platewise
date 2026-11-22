// platewise-ai: Platewise's Apple Intelligence helper.
//
// Built separately against the macOS 27 SDK (image input to the on-device model is new in macOS 27), while the
// SwiftUI app builds against the 26.5 SDK. The app runs it with one command and a JSON request on stdin;
// it answers with one JSON object on stdout. Everything runs on-device: no keys, no network.
//
//   platewise-ai status                                     -> {"available":true,"vision":true}
//   platewise-ai identify  {"image_path":..,"prompt":..}    -> {"is_food":..,"candidates":[..],..}
//   platewise-ai recipe    {"prompt":..}                    -> {"name":..,"ingredients":[..],..}
//   any failure                                             -> {"error":"readable message"}

import Foundation
import FoundationModels

@main
struct PlatewiseAI {
    static func main() async {
        let command = CommandLine.arguments.dropFirst().first ?? "status"
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let request = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        do {
            switch command {
            case "status": emit(status())
            case "identify": emitJSON(try await identify(request))
            case "recipe": emitJSON(try await recipe(request))
            default: fail("Unknown command \(command)")
            }
        } catch {
            fail(describe(error))
        }
    }

    // MARK: Output

    static func emit(_ object: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        FileHandle.standardOutput.write(data)
    }

    static func emitJSON(_ json: String) { FileHandle.standardOutput.write(Data(json.utf8)) }

    static func fail(_ message: String) -> Never {
        emit(["error": message])
        exit(0)   // the app reads the error from the JSON
    }

    // MARK: Availability

    static func status() -> [String: Any] {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return ["available": true, "vision": model.capabilities.contains(.vision)]
        case .unavailable(let reason):
            let text: String
            switch reason {
            case .deviceNotEligible: text = "This Mac doesn't support Apple Intelligence (it needs Apple silicon)."
            case .appleIntelligenceNotEnabled: text = "Apple Intelligence is turned off. Turn it on in System Settings > Apple Intelligence & Siri."
            case .modelNotReady: text = "Apple Intelligence is still downloading its model. Keep your Mac on Wi-Fi and power, then try again shortly."
            @unknown default: text = "Apple Intelligence isn't available right now."
            }
            return ["available": false, "vision": false, "reason": text]
        }
    }

    static func requireModel() throws -> SystemLanguageModel {
        let s = status()
        guard s["available"] as? Bool == true else { throw HelperError(s["reason"] as? String ?? "Apple Intelligence isn't available.") }
        return SystemLanguageModel.default
    }

    // MARK: Identify a dish from a photo

    static func identify(_ request: [String: Any]) async throws -> String {
        let model = try requireModel()
        guard model.capabilities.contains(.vision) else {
            throw HelperError("This version of Apple Intelligence can't look at photos. Type the dish name instead.")
        }
        guard let path = request["image_path"] as? String, FileManager.default.fileExists(atPath: path) else {
            throw HelperError("Couldn't read the photo.")
        }
        let candidate = DynamicGenerationSchema(name: "Candidate", properties: [
            .init(name: "name", description: "Specific dish name, e.g. 'Chicken Biryani' (add the local name in parentheses if different)", schema: string),
            .init(name: "cuisine", description: "Cuisine or region, e.g. 'Pakistani', 'Italian'", schema: string),
            .init(name: "confidence", description: "Likelihood 0-100; the candidates' confidences add up to about 100", schema: int),
            .init(name: "reason", description: "One short sentence on the visual clues", schema: string),
        ])
        // Property order is generation order: describing the photo first keeps the model from inventing a dish.
        let root = DynamicGenerationSchema(name: "DishIdentification", properties: [
            .init(name: "photo_description", description: "One plain sentence describing what the photo literally shows", schema: string),
            .init(name: "is_food", description: "True only if the photo mainly shows food or a prepared dish", schema: bool),
            .init(name: "candidates", description: "Up to 3 most likely dishes, most likely first; empty if not food",
                  schema: DynamicGenerationSchema(arrayOf: candidate, maximumElements: 3)),
            .init(name: "visible_ingredients", description: "Ingredients actually visible in the photo",
                  schema: DynamicGenerationSchema(arrayOf: string, maximumElements: 10)),
            .init(name: "note", description: "Empty, or one short sentence for the user, e.g. why the photo is hard to read", schema: string),
        ])
        let session = LanguageModelSession(model: model, instructions: """
            You are a culinary expert in a meal-planning app. Identify dishes from photos taken by home cooks. \
            First describe what the photo literally shows. If it is not food (a landscape, a person, an object), set \
            is_food to false, leave candidates and visible_ingredients empty, and explain in note. Never invent a dish. \
            For food, judge by color, texture, garnish, vessel and plating, prefer specific dish names over generic ones, \
            and give up to three candidates when the photo could be more than one dish.
            """)
        let prompt = request["prompt"] as? String ?? "Identify the dish in this photo."
        let url = URL(fileURLWithPath: path)
        let response = try await session.respond(schema: try GenerationSchema(root: root, dependencies: [])) {
            prompt
            Attachment(imageURL: url).label("Food photo")
        }
        return response.content.jsonString
    }

    // MARK: Write a recipe

    static func recipe(_ request: [String: Any]) async throws -> String {
        let model = try requireModel()
        guard let prompt = request["prompt"] as? String, !prompt.isEmpty else { throw HelperError("No dish given.") }
        let aisles = ["Produce", "Meat & Seafood", "Dairy & Eggs", "Bakery", "Pantry", "Spices & Condiments", "Frozen", "Beverages", "Other"]
        let ingredient = DynamicGenerationSchema(name: "Ingredient", properties: [
            .init(name: "name", description: "Ingredient name only, e.g. 'basmati rice'", schema: string),
            .init(name: "quantity", description: "Amount as a number, 0.5 for half; 0 if to taste", schema: double),
            .init(name: "unit", description: "cup, tbsp, tsp, g, kg, ml, oz, lb, clove, can, pinch; empty for countable items like 2 onions", schema: string),
            .init(name: "note", description: "Preparation such as 'finely chopped', or empty", schema: string),
            .init(name: "aisle", description: "Supermarket section", schema: DynamicGenerationSchema(name: "Aisle", anyOf: aisles)),
        ])
        let nutrition = DynamicGenerationSchema(name: "Nutrition", properties: [
            .init(name: "calories", description: "Estimated kcal per serving", schema: int),
            .init(name: "protein_g", schema: int),
            .init(name: "carbs_g", schema: int),
            .init(name: "fat_g", schema: int),
        ])
        let root = DynamicGenerationSchema(name: "Recipe", properties: [
            .init(name: "name", schema: string),
            .init(name: "cuisine", schema: string),
            .init(name: "summary", description: "One or two appetizing sentences", schema: string),
            .init(name: "servings", schema: int),
            .init(name: "prep_minutes", schema: int),
            .init(name: "cook_minutes", schema: int),
            .init(name: "difficulty", schema: DynamicGenerationSchema(name: "Difficulty", anyOf: ["Easy", "Medium", "Hard"])),
            .init(name: "ingredients", description: "Every ingredient in the order used",
                  schema: DynamicGenerationSchema(arrayOf: ingredient, minimumElements: 2, maximumElements: 25)),
            .init(name: "steps", description: "Clear method steps with times and heat levels",
                  schema: DynamicGenerationSchema(arrayOf: string, minimumElements: 2, maximumElements: 14)),
            .init(name: "nutrition_per_serving", schema: nutrition),
            .init(name: "tags", description: "2-4 short tags like Weeknight, Spicy", schema: DynamicGenerationSchema(arrayOf: string, maximumElements: 4)),
            .init(name: "dietary_flags", description: "Diets it fits as written: Vegetarian, Vegan, Gluten-free, Dairy-free, Halal-friendly",
                  schema: DynamicGenerationSchema(arrayOf: string, maximumElements: 5)),
            .init(name: "allergy_warnings", description: "One warning with a swap for each ingredient that conflicts with the user's allergies or diet; empty if none",
                  schema: DynamicGenerationSchema(arrayOf: string, maximumElements: 6)),
            .init(name: "tips", description: "2-3 practical tips", schema: DynamicGenerationSchema(arrayOf: string, maximumElements: 3)),
            .init(name: "youtube_search_query", description: "YouTube search that finds tutorials for exactly this dish", schema: string),
        ])
        let session = LanguageModelSession(model: model, instructions: """
            You are an experienced recipe developer in a meal-planning app. Write recipes that work the first time in a \
            home kitchen: realistic quantities, common ingredients, precise times and heat levels. Keep the dish authentic; \
            don't change it to fit the user's diet, flag conflicts in allergy_warnings with a substitution instead.
            """)
        let response = try await session.respond(to: prompt, schema: try GenerationSchema(root: root, dependencies: []))
        return response.content.jsonString
    }

    static let string = DynamicGenerationSchema(type: String.self)
    static let int = DynamicGenerationSchema(type: Int.self)
    static let double = DynamicGenerationSchema(type: Double.self)
    static let bool = DynamicGenerationSchema(type: Bool.self)

    // MARK: Errors

    struct HelperError: Error { let message: String; init(_ m: String) { message = m } }

    static func describe(_ error: Error) -> String {
        if let e = error as? HelperError { return e.message }
        if let e = error as? LanguageModelError {
            switch e {
            case .contextSizeExceeded: return "That was too much for Apple Intelligence to handle at once. Try a simpler request."
            case .guardrailViolation, .refusal: return "Apple Intelligence declined this one. Try a different photo or dish name."
            case .unsupportedLanguageOrLocale: return "Apple Intelligence doesn't support your Mac's current language for this yet."
            case .rateLimited: return "Apple Intelligence is busy. Wait a moment and try again."
            case .timeout: return "Apple Intelligence took too long. Please try again."
            case .unsupportedCapability, .unsupportedTranscriptContent:
                return "This version of Apple Intelligence can't look at photos. Type the dish name instead."
            default: return "Apple Intelligence couldn't finish: \(e.localizedDescription)"
            }
        }
        return "Apple Intelligence couldn't finish: \(error.localizedDescription)"
    }
}
