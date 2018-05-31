import Foundation
@testable import MongoSwift
import Nimble
import XCTest
import libmongoc

/// Useful extensions to the Data type for testing purposes
extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hexString.index(hexString.startIndex, offsetBy: i*2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }

        self = data
    }

    var hexDescription: String {
        return reduce("") {$0 + String(format: "%02x", $1)}
    }
}

final class DocumentTests: XCTestCase {
    static var allTests: [(String, (DocumentTests) -> () throws -> Void)] {
        return [
            ("testDocument", testDocument),
            ("testEquatable", testEquatable),
            ("testIterator", testIterator),
            ("testRawBSON", testRawBSON),
            ("testBSONCorpus", testBSONCorpus)
        ]
    }

    func testFailure() throws {
        // this works fine
        let extjson1 = "{\"a\" : [{\"$numberInt\": \"10\"}]}".data(using: .utf8)!
        let res1 = try Document(fromJSON: extjson1)
        print(res1)

        // this crashes
        let extjson2 = "{\"x\" : { \"$binary\" : {\"base64\" : \"\", \"subType\" : \"00\"}}}".data(using: .utf8)!
        let res2 = try Document(fromJSON: extjson2)
        print(res2)
    }

    func testDocument() throws {
        // A Data object to pass into test BSON Binary objects
        guard let testData = Data(base64Encoded: "//8=") else {
            XCTFail("Failed to create test binary data")
            return
        }

        // Set up test document values
        let doc: Document = [
            "string": "test string",
            "true": true,
            "false": false,
            "int": 25,
            "int32": Int32(5),
            "int64": Int64(10),
            "double": Double(15),
            "decimal128": Decimal128("1.2E+10"),
            "minkey": MinKey(),
            "maxkey": MaxKey(),
            "date": Date(timeIntervalSince1970: 5000),
            "timestamp": Timestamp(timestamp: 5, inc: 10),
            "nestedarray": [[1, 2], [Int32(3), Int32(4)]] as [[Int32]],
            "nesteddoc": ["a": 1, "b": 2, "c": false, "d": [3, 4]] as Document,
            "oid": ObjectId(fromString: "507f1f77bcf86cd799439011"),
            "regex": RegularExpression(pattern: "^abc", options: "imx"),
            "array1": [1, 2],
            "array2": ["string1", "string2"],
            "null": nil,
            "code": CodeWithScope(code: "console.log('hi');"),
            "codewscope": CodeWithScope(code: "console.log(x);", scope: ["x": 2]),
            "binary0": Binary(data: testData, subtype: BsonSubtype.binary),
            "binary1": Binary(data: testData, subtype: BsonSubtype.function),
            "binary2": Binary(data: testData, subtype: BsonSubtype.binaryDeprecated),
            "binary3": Binary(data: testData, subtype: BsonSubtype.uuidDeprecated),
            "binary4": Binary(data: testData, subtype: BsonSubtype.uuid),
            "binary5": Binary(data: testData, subtype: BsonSubtype.md5),
            "binary6": Binary(data: testData, subtype: BsonSubtype.user)
        ]

        expect(doc.count).to(equal(28))
        expect(doc.keys).to(equal(["string", "true", "false", "int", "int32", "int64", "double", "decimal128",
                                "minkey", "maxkey", "date", "timestamp", "nestedarray", "nesteddoc", "oid",
                                "regex", "array1", "array2", "null", "code", "codewscope", "binary0", "binary1",
                                "binary2", "binary3", "binary4", "binary5", "binary6"]))

        expect(doc["string"] as? String).to(equal("test string"))
        expect(doc["true"] as? Bool).to(beTrue())
        expect(doc["false"] as? Bool).to(beFalse())
        expect(doc["int"] as? Int).to(equal(25))
        expect(doc["int32"] as? Int).to(equal(5))
        expect(doc["int64"] as? Int64).to(equal(10))
        expect(doc["double"] as? Double).to(equal(15))
        expect(doc["decimal128"] as? Decimal128).to(equal(Decimal128("1.2E+10")))
        expect(doc["minkey"] as? MinKey).to(beAnInstanceOf(MinKey.self))
        expect(doc["maxkey"] as? MaxKey).to(beAnInstanceOf(MaxKey.self))
        expect(doc["date"] as? Date).to(equal(Date(timeIntervalSince1970: 5000)))
        expect(doc["timestamp"] as? Timestamp).to(equal(Timestamp(timestamp: 5, inc: 10)))
        expect(doc["oid"] as? ObjectId).to(equal(ObjectId(fromString: "507f1f77bcf86cd799439011")))

        let regex = doc["regex"] as? RegularExpression
        expect(regex).to(equal(RegularExpression(pattern: "^abc", options: "imx")))
        expect(regex?.nsRegularExpression).to(equal(try NSRegularExpression(pattern: "^abc", options: NSRegularExpression.optionsFromString("imx"))))

        expect(doc["array1"] as? [Int]).to(equal([1, 2]))
        expect(doc["array2"] as? [String]).to(equal(["string1", "string2"]))
        expect(doc["null"]).to(beNil())

        let code = doc["code"] as? CodeWithScope
        expect(code?.code).to(equal("console.log('hi');"))
        expect(code?.scope).to(beNil())

        let codewscope = doc["codewscope"] as? CodeWithScope
        expect(codewscope?.code).to(equal("console.log(x);"))
        expect(codewscope?.scope).to(equal(["x": 2]))

        expect(doc["binary0"] as? Binary).to(equal(Binary(data: testData, subtype: BsonSubtype.binary)))
        expect(doc["binary1"] as? Binary).to(equal(Binary(data: testData, subtype: BsonSubtype.function)))
        expect(doc["binary2"] as? Binary).to(equal(Binary(data: testData, subtype: BsonSubtype.binaryDeprecated)))
        expect(doc["binary3"] as? Binary).to(equal(Binary(data: testData, subtype: BsonSubtype.uuidDeprecated)))
        expect(doc["binary4"] as? Binary).to(equal(Binary(data: testData, subtype: BsonSubtype.uuid)))
        expect(doc["binary5"] as? Binary).to(equal(Binary(data: testData, subtype: BsonSubtype.md5)))
        expect(doc["binary6"] as? Binary).to(equal(Binary(data: testData, subtype: BsonSubtype.user)))

        let nestedArray = doc["nestedarray"] as? [[Int]]
        expect(nestedArray?[0]).to(equal([1, 2]))
        expect(nestedArray?[1]).to(equal([3, 4]))

        expect(doc["nesteddoc"] as? Document).to(equal(["a": 1, "b": 2, "c": false, "d": [3, 4]]))
    }

    func testIterator() {
        let doc: Document = [
            "string": "test string",
            "true": true,
            "false": false,
            "int": 25,
            "int32": Int32(5),
            "int64": Int64(10),
            "double": Double(15),
            "decimal128": Decimal128("1.2E+10"),
            "minkey": MinKey(),
            "maxkey": MaxKey(),
            "date": Date(timeIntervalSince1970: 5000),
            "timestamp": Timestamp(timestamp: 5, inc: 10)
        ]

        for (_, _) in doc { }

    }

    func testEquatable() {
        expect(["hi": true, "hello": "hi", "cat": 2] as Document)
        .to(equal(["hi": true, "hello": "hi", "cat": 2] as Document))
    }

    func testRawBSON() throws {
        let doc = try Document(fromJSON: "{\"a\" : [{\"$numberInt\": \"10\"}]}")
        let fromRawBson = Document(fromBSON: doc.rawBSON)
        expect(doc).to(equal(fromRawBson))
    }

    func testValueBehavior() {
        let doc1: Document = ["a": 1]
        var doc2 = doc1
        doc2["b"] = 2
        XCTAssertEqual(doc2["b"] as? Int, 2)
        XCTAssertNil(doc1["b"])
        XCTAssertNotEqual(doc1, doc2)
    }

    func testInvalidInt() {
        let doc1 = Document()
        let v = Int(Int32.max) + 1
        expect(try v.encode(to: doc1.data, forKey: "x")).to(throwError())

    }

    // swiftlint:disable:next cyclomatic_complexity
    func testBSONCorpus() throws {
        let SKIPPED_CORPUS_TESTS = [
            /* CDRIVER-1879, can't make Code with embedded NIL */
            "Javascript Code": ["Embedded nulls"],
            "Javascript Code with Scope": ["Unicode and embedded null in code string, empty scope"],
            /* CDRIVER-2223, legacy extended JSON $date syntax uses numbers */
            "Top-level document validity": ["Bad $date (number, not string or hash)"],
            /* VS 2013 and older is imprecise stackoverflow.com/questions/32232331 */
            "Double type": ["1.23456789012345677E+18", "-1.23456789012345677E+18"]
        ]

        let testFilesPath = self.getSpecsPath() + "/bson-corpus/tests"
        var testFiles = try FileManager.default.contentsOfDirectory(atPath: testFilesPath)
        testFiles = testFiles.filter { $0.hasSuffix(".json") }

        for fileName in testFiles {
            let testFilePath = URL(fileURLWithPath: "\(testFilesPath)/\(fileName)")
            let testFileData = try String(contentsOf: testFilePath, encoding: .utf8)
            let testFileJson = try JSONSerialization.jsonObject(with: testFileData.data(using: .utf8)!, options: [])
            guard let json = testFileJson as? [String: Any] else {
                XCTFail("Unable to convert json to dictionary")
                return
            }

            let testFileDescription = json["description"] as? String ?? "no description"
            guard let validCases = json["valid"] as? [Any] else {
                continue // there are no valid cases defined in this file
            }

            for valid in validCases {
                guard let validCase = valid as? [String: Any] else {
                    XCTFail("Unable to interpret valid case as dictionary")
                    return
                }

                let description = validCase["description"] as? String ?? "no description"
                if let skippedTests = SKIPPED_CORPUS_TESTS[testFileDescription] {
                    if skippedTests.contains(description) {
                        continue
                    }
                }

                let cB = validCase["canonical_bson"] as? String ?? ""
                guard let cBData = Data(hexString: cB) else {
                    XCTFail("Unable to interpret canonical_bson as Data")
                    return
                }

                let cEJ = validCase["canonical_extjson"] as? String ?? ""
                guard let cEJData = cEJ.data(using: .utf8) else {
                    XCTFail("Unable to interpret canonical_extjson as Data")
                    return
                }

                let lossy = validCase["lossy"] as? Bool ?? false

                // for cB input:
                // native_to_bson( bson_to_native(cB) ) = cB
                expect(Document(fromBSON: cBData).rawBSON).to(equal(cBData))

                // native_to_canonical_extended_json( bson_to_native(cB) ) = cEJ
                expect(Document(fromBSON: cBData).canonicalExtendedJSON).to(cleanEqual(cEJ))

                // native_to_relaxed_extended_json( bson_to_native(cB) ) = rEJ (if rEJ exists)
                if let rEJ = validCase["relaxed_extjson"] as? String {
                     expect(Document(fromBSON: cBData).extendedJSON).to(cleanEqual(rEJ))
                }

                // for cEJ input:
                // native_to_canonical_extended_json( json_to_native(cEJ) ) = cEJ
                expect(try Document(fromJSON: cEJData).canonicalExtendedJSON).to(cleanEqual(cEJ))

                // native_to_canonical_extended_json( json_to_native(cEJ) ) = cEJ
                if !lossy {
                    expect(try Document(fromJSON: cEJData).rawBSON).to(equal(cBData))
                }

                // for dB input (if it exists):
                if let dB = validCase["degenerate_bson"] as? String {
                    guard let dBData = Data(hexString: dB) else {
                        XCTFail("Unable to interpret degenerate_bson as Data")
                        return
                    }

                    // bson_to_canonical_extended_json(dB) = cEJ
                    expect(Document(fromBSON: dBData).canonicalExtendedJSON).to(cleanEqual(cEJ))

                    // bson_to_relaxed_extended_json(dB) = rEJ (if rEJ exists)
                    if let rEJ = validCase["relaxed_extjson"] as? String {
                        expect(Document(fromBSON: dBData).extendedJSON).to(cleanEqual(rEJ))
                    }
                }

                // for dEJ input (if it exists):
                if let dEJ = validCase["degenerate_extjson"] as? String {
                    // native_to_canonical_extended_json( json_to_native(dEJ) ) = cEJ
                    expect(try Document(fromJSON: dEJ).canonicalExtendedJSON).to(cleanEqual(cEJ))

                    // native_to_bson( json_to_native(dEJ) ) = cB (unless lossy)
                    if !lossy {
                        expect(try Document(fromJSON: dEJ).rawBSON).to(equal(cBData))
                    }
                }

                // for rEJ input (if it exists):
                if let rEJ = validCase["relaxed_extjson"] as? String {
                    // native_to_relaxed_extended_json( json_to_native(rEJ) ) = rEJ
                    expect(try Document(fromJSON: rEJ).extendedJSON).to(cleanEqual(rEJ))
                }
            }
        }
    }

    func testMerge() throws {
        var doc1: Document = ["a": 1]
        try doc1.merge(["b": 2])
        expect(doc1).to(equal(["a": 1, "b": 2]))
    }
}
