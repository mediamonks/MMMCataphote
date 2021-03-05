//
// MMMCataphote. Part of MMMTemple suite.
// Copyright (C) 2016-2021 MediaMonks. All rights reserved.
//

import XCTest
@testable import MMMCataphote

class MMMCataphoteTestCase: XCTestCase {

	struct A: Decodable {

		let primitiveString: String
		let primitiveInt: Int
		let objectC: C

		let arrayInt: [Int]
		let arrayOptString: [String?]

		enum Enum: String, Decodable {
			case invalid = "dummy" // Enums are not supported unless they have a "dummy" case
			case a
		}
		let e: Enum

		let dictStringObject: [String: C]
		let dictStringArrayInt: [String: [Int]]
		let dictStringDictStringInt: [String: [String: Int]]

		let dInt: D<Int>
		let dArrayString: D<[String]>
	}

	class E: Decodable {
	}

	class F: Decodable {
		let i: Int
	}

	struct C: Decodable {

		let ca: Double
		let cb: Int? = nil // Will be skipped in the reflection.
		let cc: [Int]

		let optObjectF: F?
		let objectE: E

		enum CodingKeys: String, CodingKey {
			case ca = "ca_renamed"
			// cb skipped
			case cc
			case optObjectF
			case objectE
		}
	}

	// This won't be visible as itself.
	struct D<T: Decodable>: Decodable {
		let t: T
		init(from decoder: Decoder) throws {
			self.t = try T.init(from: decoder)
		}
	}

	public func testBasics() {
		let r = MMMCataphote.reflect(A.self)
		let f = MMMCataphote.Object(name: "F", fields: [
			.init(name: "i", typeInfo: .primitive("Int"	))
		])
		let c = MMMCataphote.Object(name: "C", fields: [
			.init(name: "ca_renamed", typeInfo: .primitive("Double")),
			.init(name: "cc", typeInfo: .array(.primitive("Int"))),
			.init(name: "objectE", typeInfo: .unknown),
			.init(name: "optObjectF", typeInfo: .optional(.object(f)))
		])
		let a = MMMCataphote.Object(name: "A", fields: [
			.init(name: "arrayInt", typeInfo: .array(.primitive("Int"))),
			.init(name: "arrayOptString", typeInfo: .array(.optional(.primitive("String")))),
			.init(name: "dArrayString", typeInfo: .array(.primitive("String"))),
			.init(name: "dInt", typeInfo: .primitive("Int")),
			.init(name: "dictStringArrayInt", typeInfo: .dictionary(.primitive("String"), .array(.primitive("Int")))),
			.init(name: "dictStringDictStringInt", typeInfo: .dictionary(.primitive("String"), .dictionary(.primitive("String"), .primitive("Int")))),
			.init(name: "dictStringObject", typeInfo: .dictionary(.primitive("String"), .object(c))),
			.init(name: "e", typeInfo: .primitive("String")),
			.init(name: "objectC", typeInfo: .object(c)),
			.init(name: "primitiveInt", typeInfo: .primitive("Int")),
			.init(name: "primitiveString", typeInfo: .primitive("String"))
		])
		XCTAssertEqual(
			r,
			MMMCataphote.Reflection(
				typeInfo: .object(a),
				objects: .init(uniqueKeysWithValues: [a, c, f].map { ($0.name, $0) })
			)
		)
	}

	struct URLStruct: Decodable {
		var url: URL
		var urlArray: [URL]
	}

	// There was a problem with URLs in the initial version, let's check them.
	public func testURL() {
		let r = MMMCataphote.reflect(URLStruct.self)
		let a = MMMCataphote.Object(name: "URLStruct", fields: [
			.init(name: "url", typeInfo: .primitive("String")),
			.init(name: "urlArray", typeInfo: .array(.primitive("String")))
		])
		XCTAssertEqual(
			r,
			MMMCataphote.Reflection(
				typeInfo: .object(a),
				objects: ["URLStruct": a]
			)
		)
	}

	// Just a short example for the README.
	public func testExample() {

		struct Person: Decodable {
			let id: Int
			let name: String
			let height: Height
		}

		struct Height: Decodable {
			let height: Double
		}

		let r = MMMCataphote.reflect(Person.self)
		print(r)
	}
}
