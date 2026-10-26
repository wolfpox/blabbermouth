@tool
class_name BlabberWord
extends Resource
## A word or phrase in a BlabberVocabulary, with its recordings ("takes").
## Each time a line says it, one take is played.

## As written, e.g. "Hello" or "thank you". Matching ignores case and punctuation.
@export var text := ""
## The recordings. More than one gives variety: the same take isn't used twice in a row.
@export var takes: Array[BlabberClip] = []


static func create(p_text: String) -> BlabberWord:
	var w := BlabberWord.new()
	w.text = p_text.strip_edges()
	return w


## The name used to look the word up: lowercase words with single spaces.
var key: String:
	get:
		return BlabberVocabulary.key_of(text)
