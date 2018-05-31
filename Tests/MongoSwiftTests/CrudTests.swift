@testable import MongoSwift
import Foundation
import Nimble
import XCTest

// Files to skip because we don't currently support the operations they test.
private var skippedFiles = [
    "bulkWrite-arrayFilters",
    "findOneAndDelete-collation",
    "findOneAndDelete",
    "findOneAndReplace-collation",
    "findOneAndReplace-upsert",
    "findOneAndReplace",
    "findOneAndUpdate-arrayFilters",
    "findOneAndUpdate-collation",
    "findOneAndUpdate",
    // TODO: once CDRIVER-2527 changes available, stop skipping these 
    "deleteMany-collation",
    "deleteOne-collation"
]

internal extension Document {
    init(fromJSONFile file: URL) throws {
        let jsonString = try String(contentsOf: file, encoding: .utf8)
        try self.init(fromJSON: jsonString)
    }
}

final class CrudTests: XCTestCase {

    static var allTests: [(String, (CrudTests) -> () throws -> Void)] {
        return [
            ("testReads", testReads),
            ("testWrites", testWrites)
        ]
    }

    // Teardown at the very end of the suite by dropping the "crudTests" db.
    override class func tearDown() {
        super.tearDown()
        do {
            try MongoClient().db("crudTests").drop()
        } catch {
            print("Dropping test db crudTests failed: \(error)")
        }
    }

    // Run tests for .json files at the provided path
    func doTests(forPath: String) throws {
        let db = try MongoClient().db("crudTests")
        for file in try parseFiles(atPath: forPath) {
            // later on when running with different server versions, this would
            // be the place to check file.minServerVersion/maxServerVersion

            print("\n------------\nExecuting tests from file \(forPath)/\(file.name).json...\n")

            // For each file, execute the test cases contained in it
            for (i, test) in file.tests.enumerated() {

                print("Executing test: \(test.description)")

                // for each test case:
                // 1) create a unique collection to use
                // 2) insert the data specified by this test file 
                // 3) execute the test according to the type's execute method
                // 4) verify that expected data is present
                // 5) drop the collection to clean up
                let collection = try db.collection("\(file.name)+\(i)")
                _ = try collection.insertMany(file.data)
                try test.execute(usingCollection: collection)
                try test.verifyData(testCollection: collection, db: db)
                try collection.drop()
            }
        }
        print() // for readability of results
    }

    // Go through each .json file at the given path and parse the information in it
    // into a corresponding CrudTestFile with a [CrudTest]
    private func parseFiles(atPath path: String) throws -> [CrudTestFile] {
        var tests = [CrudTestFile]()
        let testFiles = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".json") }
        for fileName in testFiles {
            let name = fileName.components(separatedBy: ".")[0]
            if skippedFiles.contains(name) { continue }
            let testFilePath = URL(fileURLWithPath: "\(path)/\(fileName)")
            let asDocument = try Document(fromJSONFile: testFilePath)
            tests.append(try CrudTestFile(fromDocument: asDocument, name: fileName))
        }
        return tests
    }

    // Run all the tests at the /read path
    func testReads() throws {
        let testFilesPath = self.getSpecsPath() + "/crud/tests/read"
        try doTests(forPath: testFilesPath)
    }

    // Run all the tests at the /write path
    func testWrites() throws {
        let testFilesPath = self.getSpecsPath() + "/crud/tests/write"
        try doTests(forPath: testFilesPath)
    }
}

/// A container for the data from a single .json file. 
private struct CrudTestFile {
    let data: [Document]
    let tests: [CrudTest]
    let minServerVersion: String?
    let maxServerVersion: String?
    let name: String

    /// Initializes a new `CrudTestFile` from a `Document`. 
    init(fromDocument document: Document, name: String) throws {
        self.data = try document.get("data")
        let tests: [Document] = try document.get("tests")
        self.tests = try tests.map { try makeCrudTest($0) }
        self.minServerVersion = document["minServerVersion"] as? String
        self.maxServerVersion = document["maxServerVersion"] as? String
        self.name = name.components(separatedBy: ".")[0]
    }
}

/// Initializes a new `CrudTest` of the appropriate subclass from a `Document` 
private func makeCrudTest(_ doc: Document) throws -> CrudTest {
    let operation: Document = try doc.get("operation")
    let opName: String = try operation.get("name")
    guard let type = testTypeMap[opName] else {
        throw TestError(message: "Unknown operation name \(opName)")
    }
    return try type.init(doc)
}

// Maps operation names to the appropriate test class to use for them. 
private var testTypeMap: [String: CrudTest.Type] = [
    "aggregate": AggregateTest.self,
    "count": CountTest.self,
    "deleteMany": DeleteTest.self,
    "deleteOne": DeleteTest.self,
    "distinct": DistinctTest.self,
    "find": FindTest.self,
    "insertMany": InsertManyTest.self,
    "insertOne": InsertOneTest.self,
    "replaceOne": ReplaceOneTest.self,
    "updateMany": UpdateTest.self,
    "updateOne": UpdateTest.self
]

/// An abstract class to represent a single test within a CrudTestFile. Subclasses must
/// implement the `execute` method themselves. 
private class CrudTest {
    let description: String
    let operationName: String
    let args: Document
    let result: BsonValue?
    let collection: Document?
    var collation: Document? { return self.args["collation"] as? Document }
    var sort: Document? { return self.args["sort"] as? Document }
    var skip: Int64? { if let s = self.args["skip"] as? Int { return Int64(s) } else { return nil } }
    var limit: Int64? { if let l = self.args["limit"] as? Int { return Int64(l) } else { return nil } }
    var batchSize: Int32? { if let b = self.args["batchSize"] as? Int { return Int32(b) } else { return nil } }
    var upsert: Bool? { return self.args["upsert"] as? Bool }

    /// Initializes a new `CrudTest` from a `Document`. 
    required init(_ test: Document) throws {
        self.description = try test.get("description")
        let operation: Document = try test.get("operation")
        self.operationName = try operation.get("name")
        self.args = try operation.get("arguments")
        let outcome: Document = try test.get("outcome")
        self.result = outcome["result"]
        self.collection = outcome["collection"] as? Document
    }

    // Subclasses should implement `execute` according to the particular operation(s) they are for. 
    func execute(usingCollection coll: MongoCollection<Document>) throws { XCTFail("Unimplemented") }

    // If the test has a `collection` field in its `outcome`, verify that the expected
    // data is present. If there is no `collection` field, do nothing. 
    func verifyData(testCollection coll: MongoCollection<Document>, db: MongoDatabase) throws {
        guard let collection = self.collection else { return } // only  some tests have data to verify
        // if a name is not specified, check the current collection
        var collToCheck = coll
        if let name = collection["name"] as? String {
            collToCheck = try db.collection(name)
        }
        expect(Array(try collToCheck.find([:]))).to(equal(try collection.get("data")))
    }

    // Given an `UpdateResult`, verify that it matches the expected results in this `CrudTest`. 
    // Meant for use by subclasses whose operations return `UpdateResult`s, such as `UpdateTest` 
    // and `ReplaceOneTest`. 
    func verifyUpdateResult(_ result: UpdateResult?) {
        let expected = self.result as? Document
        expect(result?.matchedCount).to(equal(expected?["matchedCount"] as? Int))
        expect(result?.modifiedCount).to(equal(expected?["modifiedCount"] as? Int))
        let upsertedId = result?.upsertedId as? Double
        if upsertedId != nil {
            expect(upsertedId).to(equal(Double(expected?["upsertedId"] as! Int)))
        } else {
            expect(expected?["upsertedId"] as? Int).to(beNil())
        }
    }
}

/// A class for executing `aggregate` tests
private class AggregateTest: CrudTest {
    override func execute(usingCollection coll: MongoCollection<Document>) throws {
        let pipeline: [Document] = try self.args.get("pipeline")
        let options = AggregateOptions(batchSize: self.batchSize, collation: self.collation)
        let cursor = try coll.aggregate(pipeline, options: options)
        if self.collection != nil {
            // this is $out case - we need to iterate the cursor once in 
            // order to make the aggregation happen. there is nothing in
            // the cursor to verify, but verifyData() will check that the
            // $out collection has the new data.
            expect(cursor.next()).to(beNil())
        } else {
            // if not $out, verify that the cursor contains the expected documents. 
            expect(Array(cursor)).to(equal(self.result as? [Document]))
        }
    }
}

/// A class for executing `count` tests
private class CountTest: CrudTest {
    override func execute(usingCollection coll: MongoCollection<Document>) throws {
        let filter: Document = try self.args.get("filter")
        let options = CountOptions(collation: self.collation, limit: self.limit, skip: self.skip)
        let result = try coll.count(filter, options: options)
        expect(result).to(equal(self.result as? Int))
    }
}

/// A class for executing `deleteOne` and `deleteMany` tests
private class DeleteTest: CrudTest {
    override func execute(usingCollection coll: MongoCollection<Document>) throws {
        let filter: Document = try self.args.get("filter")
        let options = DeleteOptions(collation: self.collation)
        let result: DeleteResult?
        if self.operationName == "deleteOne" {
            result = try coll.deleteOne(filter, options: options)
        } else {
            result = try coll.deleteMany(filter, options: options)
        }
        let expected = self.result as? Document
        // the only value in a DeleteResult is `deletedCount`
        expect(result?.deletedCount).to(equal(expected?["deletedCount"] as? Int))
    }
}

/// A class for executing `distinct` tests
private class DistinctTest: CrudTest {
    override func execute(usingCollection coll: MongoCollection<Document>) throws {
        let filter = self.args["filter"] as? Document
        let fieldName: String = try self.args.get("fieldName")
        let options = DistinctOptions(collation: self.collation)
        let distinct = try coll.distinct(fieldName: fieldName, filter: filter ?? [:], options: options)
        // `distinct` returns a cursor with just one document: {values: [values...], ok: 1.0 }
        expect(distinct.next()).to(equal(["values": self.result, "ok": 1.0] as Document))
        expect(distinct.next()).to(beNil())
    }
}

/// A class for executing `find` tests
private class FindTest: CrudTest {
    override func execute(usingCollection coll: MongoCollection<Document>) throws {
        let filter: Document = try self.args.get("filter")
        let options = FindOptions(batchSize: batchSize, collation: collation, limit: self.limit,
                                    skip: self.skip, sort: self.sort)
        let result = try Array(coll.find(filter, options: options))
        expect(result).to(equal(self.result as? [Document]))
    }
}

/// A class for executing `insertMany` tests
private class InsertManyTest: CrudTest {
    override func execute(usingCollection coll: MongoCollection<Document>) throws {
        let docs: [Document] = try self.args.get("documents")
        let result = try coll.insertMany(docs)

        let insertedIds = result?.insertedIds
        expect(insertedIds).toNot(beNil())

        // Convert the result's [Int64: BsonValue] to a Document for easy comparison
        var reformattedResults = Document()
        for (index, id) in insertedIds! {
            reformattedResults[String(index)] = id
        }

        let expected = self.result as? Document
        expect(reformattedResults).to(equal(expected?["insertedIds"] as? Document))
    }
}

/// A Class for executing `insertOne` tests
private class InsertOneTest: CrudTest {
    override func execute(usingCollection coll: MongoCollection<Document>) throws {
        let doc: Document = try self.args.get("document")
        let result = try coll.insertOne(doc)
        expect(result?.insertedId as? Double).to(equal(Double(doc["_id"] as! Int)))
    }
}

/// A class for executing `replaceOne` tests
private class ReplaceOneTest: CrudTest {
    override func execute(usingCollection coll: MongoCollection<Document>) throws {
        let filter: Document = try self.args.get("filter")
        let replacement: Document = try self.args.get("replacement")
        let options = ReplaceOptions(collation: self.collation, upsert: self.upsert)
        let result = try coll.replaceOne(filter: filter, replacement: replacement, options: options)
        self.verifyUpdateResult(result)
    }
}

/// A class for executing `updateOne` and `updateMany` tests
private class UpdateTest: CrudTest {
    override func execute(usingCollection coll: MongoCollection<Document>) throws {
        let filter: Document = try self.args.get("filter")
        let update: Document = try self.args.get("update")
        let arrayFilters = self.args["arrayFilters"] as? [Document]
        let options = UpdateOptions(arrayFilters: arrayFilters, collation: self.collation, upsert: self.upsert)
        let result: UpdateResult?
        if self.operationName == "updateOne" {
            result = try coll.updateOne(filter: filter, update: update, options: options)
        } else {
            result = try coll.updateMany(filter: filter, update: update, options: options)
        }
        self.verifyUpdateResult(result)
    }
}

internal struct TestError: LocalizedError {
    var message: String
    public var errorDescription: String { return self.message }
}
