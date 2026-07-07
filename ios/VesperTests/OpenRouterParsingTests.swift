import XCTest
@testable import Vesper

final class OpenRouterParsingTests: XCTestCase {

    func testParseCommandFromWellFormedArguments() {
        let json = """
        {"action":"list_directory","args":{"path":"/ext/subghz"},"justification":"look","expected_effect":"list"}
        """
        let (command, error) = OpenRouterClient.parseCommand(arguments: json)
        XCTAssertNil(error)
        XCTAssertEqual(command?.action, .listDirectory)
        XCTAssertEqual(command?.args.path, "/ext/subghz")
    }

    func testParseCommandToleratesDoubleEncodedArguments() {
        // Some models return the args as a JSON *string*.
        let inner = "{\"action\":\"get_device_info\",\"args\":{},\"justification\":\"x\",\"expected_effect\":\"y\"}"
        let doubleEncoded = try! String(data: JSONEncoder().encode(inner), encoding: .utf8)!
        let (command, _) = OpenRouterClient.parseCommand(arguments: doubleEncoded)
        XCTAssertEqual(command?.action, .getDeviceInfo)
    }

    func testParseCommandToleratesStringRecursiveFlag() {
        let json = """
        {"action":"delete","args":{"path":"/ext/x","recursive":"true"},"justification":"j","expected_effect":"e"}
        """
        let (command, _) = OpenRouterClient.parseCommand(arguments: json)
        XCTAssertEqual(command?.action, .delete)
        XCTAssertEqual(command?.args.recursive, true)
    }

    func testParseCommandRejectsGarbage() {
        let (command, error) = OpenRouterClient.parseCommand(arguments: "not json at all")
        XCTAssertNil(command)
        XCTAssertNotNil(error)
    }

    func testParseResponseExtractsToolCall() {
        let body = """
        {"model":"test/model","choices":[{"message":{"content":"ok","tool_calls":[
        {"id":"call_1","type":"function","function":{"name":"execute_command",
        "arguments":"{\\"action\\":\\"read_file\\",\\"args\\":{\\"path\\":\\"/ext/a\\"},\\"justification\\":\\"j\\",\\"expected_effect\\":\\"e\\"}"}}]}}]}
        """
        guard case let .success(content, toolCalls, model) = OpenRouterClient.parseResponse(Data(body.utf8)) else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(content, "ok")
        XCTAssertEqual(model, "test/model")
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls.first?.command?.action, .readFile)
    }

    func testParseResponseSurfacesApiError() {
        let body = #"{"error":{"message":"insufficient credits"}}"#
        guard case let .failure(message) = OpenRouterClient.parseResponse(Data(body.utf8)) else {
            return XCTFail("Expected failure")
        }
        XCTAssertTrue(message.contains("insufficient credits"))
    }

    func testToolSchemaEnumeratesAllActions() {
        let function = OpenRouterClient.toolSchema["function"] as? [String: Any]
        let parameters = function?["parameters"] as? [String: Any]
        let properties = parameters?["properties"] as? [String: Any]
        let action = properties?["action"] as? [String: Any]
        let cases = action?["enum"] as? [String]
        XCTAssertEqual(cases?.count, CommandAction.allCases.count)
    }
}
