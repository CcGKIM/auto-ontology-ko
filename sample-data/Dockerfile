# Sample-data loader: seeds the Wide World Importers sample database into the
# compose Postgres, once, then exits. Used by docker-compose.sample.yml.
#
# The seed script and its CSV/DDL files come from NVIDIA/auto-ontology-eval,
# pinned to a commit and fetched with a sparse checkout so the image carries
# only the one dataset it needs (~240 MB) rather than the whole repository.
FROM python:3.12-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# The seed script imports only these two packages.
RUN pip install --no-cache-dir "psycopg[binary]" python-dotenv

ARG EVAL_REPO=https://github.com/NVIDIA/auto-ontology-eval.git
ARG EVAL_REF=ec41b2c5b795637759297b90c1d19b42693200f9
RUN git init -q /eval \
 && cd /eval \
 && git remote add origin "$EVAL_REPO" \
 && git config core.sparseCheckout true \
 && printf 'datasets/wideworldimporters/\nscripts/seed/seed_wwi.py\n' > .git/info/sparse-checkout \
 && git fetch -q --depth 1 origin "$EVAL_REF" \
 && git checkout -q FETCH_HEAD

COPY check_seeded.py enable_compile.py seed.sh questions.txt /
# A Windows checkout may have turned these into CRLF, which makes /bin/sh fail
# with "No such file or directory". Strip the carriage returns defensively.
RUN sed -i 's/\r$//' /seed.sh /check_seeded.py /enable_compile.py /questions.txt && chmod +x /seed.sh

# The seed script opens CSVs without an encoding; force UTF-8 regardless of locale.
ENV PYTHONUTF8=1

CMD ["/seed.sh"]
