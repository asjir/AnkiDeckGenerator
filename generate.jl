using Pkg
Pkg.instantiate()
using DataFrames, CSV, DataStructures, Downloads
using Statistics: mean
using Unicode: ispunct
using ProgressBars: tqdm

AUDIO_USERNAMES = ["driini"]
SENTENCE_PAIRS = "data/Sentence pairs in German-English - 2025-06-21.csv"
# how many clozes to create
TOP_N = 3000
# if at least 30% of occurrences of a word are capitalised assume it's a proper noun
PROPER_NOUN_THRESHOLD = 1.  # 0.3

# Sentence id [tab] Audio id [tab] Username [tab] License [tab] Attribution URL
audios = CSV.read("data/sentences_with_audio.csv", DataFrame; header=0)
audios = rename!(audios, ["sid", "aid", "uname", "lic", "url"])
filter!(r -> r.uname ∈ AUDIO_USERNAMES, audios)

trans = CSV.read(SENTENCE_PAIRS, DataFrame; header=1)[:, 1:4]
trans = rename!(trans, ["oid", "otx", "tid", "ttx"])
println("Make sure these are the language you're learning!:\n", trans.otx[1:3],
    "\nand not the language you know")
audiod = innerjoin(trans, audios; on="oid" => "sid", matchmissing=:notequal)

normalise(text) = lowercase(filter(!ispunct, text))
isspaceorpunct(x) = isspace(x) || ispunct(x)
potentially_proper_nouns(words) = filter(x -> titlecase(x) == x, words)[2:end]
split_filterempty(x) = filter(!isempty, split(x, isspaceorpunct))
split_norm(x) = filter(!isempty, normalise.(split(x, isspaceorpunct)))

counts = counter(Iterators.flatten(split_norm.(trans.otx)))
counts_sorted = sort(collect(counts); by=last, rev=true)

# I try to remove proper nouns
counts_proper = counter(normalise.(Iterators.flatten(potentially_proper_nouns.(split_filterempty.(trans.otx)))))
counts_proper_sorted = sort(collect(counts_proper); by=last, rev=true)
proper_freq = first.(counts_proper_sorted) .=> last.(counts_proper_sorted) ./ getindex.([counts], normalise.(first.(counts_proper_sorted)))
proper_words = Set(first.(filter(>(PROPER_NOUN_THRESHOLD) ∘ last, proper_freq)))

counts_sorted = filter(x -> first(x) ∉ proper_words, counts_sorted)
# Adjust PROPER_NOUN_THRESHOLD if wrong, e.g. set to 1 for German...
@assert length(counts_sorted) / length(counts) > 0.75

println("Now top2000.txt will give you the most common words and their frequencies - check they're fine.")
write("top2000.txt", join(string.(counts_sorted[1:2000]), "\n"))

# the default 2500 below shouldn't matter much - it's just proper nouns
wordranks = DefaultDict(2500, (first.(counts_sorted) .=> 1:length(counts_sorted))...)
getwordrank(word) = wordranks[normalise(word)]

rank(row) = mean(getwordrank.(split_filterempty(row.otx))) + 3length(row.otx)
audiod[!, "rank"] .= rank.(eachrow(audiod))
sort!(audiod, :rank)
audiod = combine(groupby(audiod, :otx), first)

audiod[!, "otx_tokenised"] = split_norm.(audiod.otx)
# counts have been taken over all sentences not only those with audio so filter for those with audio
available_words = Set(Iterators.filter(x -> length(x) > 2, Iterators.flatten(audiod.otx_tokenised)))

words = first.(counts_sorted)
# take top N that are in sentences with audio
words = collect(Iterators.take(
    Iterators.filter(x -> x ∈ available_words, words), TOP_N
))

usedrows = Set{DataFrameRow}()
result = Dict()
rows = eachrow(audiod)

for word ∈ tqdm(words)
    idx = findfirst(row -> (word in row.otx_tokenised) && (row ∉ usedrows), rows)
    isnothing(idx) && (idx = findfirst(row -> (word in row.otx_tokenised), rows))
    # find which position is our word at
    row = rows[idx]
    push!(usedrows, row)
    result[word] = row
end

df2 = DataFrame(getindex.([result], words))

denorm(word, sentence) =
    let wordpos = findfirst(==(word), split_norm(sentence))
        split(sentence, isspaceorpunct)[wordpos]
    end

formclause(word, sentence) =
    let word = denorm(word, sentence)
        # replace(sentence, word=>"{{c1::$word}}")
        c = "(\\s+)|([\\p{P}\\p{S}])"  # captures space or punctuation
        replace(sentence, Regex("(?<a>$c|^)(?<b>$word)(?<c>$c|\$)") => s"\g<a>{{c1::\g<b>}}\g<c>")
    end

df2.Text = df2.otx  # hacky
df2.Text = formclause.(words, df2.Text)

df2.Extra = df2.ttx
df2[!, "Difficulty"] = 1:length(df2.Text)
df2[!, "Audio"] = map(id -> "[sound:tatoebaaudio$id.mp3]", df2.aid)
CSV.write(open("autodeck.csv", "w+"), df2[:, ["Text", "Extra", "Difficulty", "Audio"]])


dl_id(id) =
    let fname = "audio/tatoebaaudio$id.mp3"
        !isfile(fname) && Downloads.download("https://tatoeba.org/audio/download/$id", fname)
    end

println("downloading...")

isdir("audio") || mkdir("audio")

for aid in tqdm(df2.aid)
    dl_id(aid)
end