# ferret

semantic search for [Hack Club](https://hackclub.com) Unified YSWS DB projects. it pulls project data from airtable, embeds descriptions into vectors, and lets you search them with a ranking pipeline that's almost good enough?

this is a janky first pass. it works, it's useful, and someone can and should do way better. the concept needs to exist — "what if you could actually find things in the YSWS project database" — and this is the minimum viable execution of that concept.

## how it works

data flows through three steps:

1. **download** — pulls a CSV export from airtable via [scaretable](https://github.com/hackclub/scaretable)
2. **ingest** — cleans descriptions (strips markdown, urls, whitespace) and upserts into sqlite
3. **vectorize** — embeds descriptions with [all-mpnet-base-v2](https://huggingface.co/sentence-transformers/all-mpnet-base-v2) and indexes them in [sqlite-vec](https://github.com/asg017/sqlite-vec), plus builds an FTS5 full-text index with porter stemming

a cron job runs all three nightly at 3am UTC.

## the ranking algorithm

search uses a three-stage retrieval pipeline. it's not novel — it's a bog-standard pattern from information retrieval research, just crammed into a single sqlite database and a ruby process.

### stage 1: dual retrieval

two parallel searches run against the query:

- **vector search** — the query gets embedded with the same model (all-mpnet-base-v2) and run as a KNN search over sqlite-vec. this finds semantically similar descriptions even when they don't share exact words.
- **full-text search** — FTS5 with porter stemming and basic query expansion (e.g. "game" expands to `"game" OR "games" OR "gaming"`). this catches exact keyword matches that embedding models sometimes miss.

### stage 2: reciprocal rank fusion (RRF)

the two result lists get merged using [Reciprocal Rank Fusion](https://plg.uwaterloo.ca/~gvcormac/cormacksigir09-rrf.pdf) (Cormack et al., 2009). the idea is dead simple: for each result, sum `weight / (k + rank)` across both lists. this gives you a combined ranking without needing to normalize wildly different score distributions.

vector search gets 2x weight over FTS because in practice the embeddings find more interesting stuff and the keyword matches are noisier. k=60, which is the standard value from the paper.

### stage 3: cross-encoder reranking

the top candidates from RRF get reranked by a cross-encoder ([ms-marco-MiniLM-L-6-v2](https://huggingface.co/cross-encoder/ms-marco-MiniLM-L-6-v2)). cross-encoders are more accurate than bi-encoders because they see the query and document together, but they're too slow to run over the whole corpus — so you use the cheap retrieval stage to get candidates, then the expensive reranker to sort them properly.

this is the [retrieve-then-rerank](https://arxiv.org/abs/2101.05667) pattern. it's table stakes in search. nothing fancy here.

a few heuristics on top:

- **description length penalty** — short descriptions (under 100 chars) get their reranker scores discounted proportionally. short descriptions are noisy and tend to get inflated scores.
- **score floor** — anything below a 0.01 reranker score gets dropped. below that threshold it's just noise.
- **exclusion terms** — you can prefix words with `-` to exclude them (e.g. `game -platformer`). word boundary matching so compound words like "orpheus-engine" don't get caught.

## what's here

```
app.rb          sinatra app, search endpoint, ranking logic
lib/db.rb       sqlite schema, connection setup, text cleaning
bin/download    pull CSV from airtable
bin/ingest      parse CSV into sqlite
bin/vectorize   embed descriptions, build vec + fts indexes
bin/refresh     run all three in sequence
bin/entrypoint  docker entrypoint (starts cron + web server)
```

## running it

you need ruby 3.3+ and the env vars `SCARETABLE_BASE_ID` and `SCARETABLE_SHARE_ID` pointing at your airtable share.

```sh
bundle install
bin/refresh         # download, ingest, vectorize
ruby app.rb         # http://localhost:4567
```

or with docker:

```sh
docker build -t ferret .
docker run -p 4567:4567 --env-file .env ferret
```

## what should be better

basically everything. some specific things:

- the query expansion table is hand-written and tiny. a real system would use something like wordnet or learned query reformulation.
- there's no learning-to-rank. the RRF weights and reranker floor are hand-tuned vibes. you could train an actual model on click data if you had any.
- embedding model is run in-process in ruby via ONNX (informers gem). it works but it's not fast. a dedicated embedding service or precomputed index would be better.
- the reranker candidate pool size (37) was picked by "what feels fast enough." there's probably an optimal number and this isn't it.
- no caching. every search re-embeds the query and re-runs the whole pipeline.
- the frontend is one ERB file and a CSS file. it's fine. it's a search box.

if you want to make this better, please do. the bones are here. the concept is the part that matters.