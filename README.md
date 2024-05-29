# Generator for Anki decks to learn languages using Tatoeaba sentences

## How to use:

* Download sentence pairs for the languages you want
* They'll be in TSV - so I open them in numbers and reexport as CSV: `Sentence pairs.csv`
* Find which users for your language have good/consistent audio.
* Update the usernames and Sentence pair file in generate.jl
* Run it.
* Put audio files from the audio folder into anki media folder
  * for me it's `~/Library/Application Support/Anki2/User 1/collection.media`
* Import deck into anki.

## Procedure description
i.e. what the program does

* Go through all sentences counting up occurrences of each word.
* Filter out:
  * proper nouns - right now it's an approximate solution.
  * words that don't occur in the read sentences
* Pick the top 3000 most common words left.
* Go over each word finding the easiest sentence containing it, which hasn't been used for a previous word.
  * If no such sentence found then reuse a sentence.
  * This gives a list of pairs: (*word*, *sentence*)
* For each pair turn the *sentence* into a cloze with the *word* deleted.
* Download audio, create deck.
