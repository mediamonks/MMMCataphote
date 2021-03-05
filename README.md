# MMMCataphote

Limited reflection for Decodable types.

(This is a part of `MMMTemple` suite of iOS libraries we use at [MediaMonks](https://www.mediamonks.com/).)

The main objective for this is to be able to automatically generate lists of object fields and child entities to be
included into responses when working with JSONAPI-style responses.

Limitations:
1) there is very limited support for enum fields (only the ones that can decode from a string "dummy");
2) any dictionary is assumed to have `String` keys, could be resolved by parsing type names;
3) it might not work well with `Decodable`s that use custom initializers.

## Installation

Podfile:

```
source 'https://github.com/mediamonks/MMMSpecs.git'
source 'https://cdn.cocoapods.org/'
...
pod 'MMMCataphote'
```

## Usage

A quick example here:

	import MMMCataphote
	
	struct Person: Decodable {
		let id: Int
		let name: String
		let height: Height
	}
	
	struct Height: Decodable {
		let height: Double
	}
	
	print(MMMCataphote.reflect(Person.self))

Prints the following:

	Object(Person) where:
	
	Height:
	 - height: Double
	
	Person:
	 - height: Object(Height)
	 - id: Int
	 - name: String

I.e. the value returned by `MMMCataphote.reflect` can be browsed to automatically build the lists of fields or entities
to include into JSONAPI-like responses, for example.

---
