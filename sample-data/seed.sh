#!/bin/sh
# Load the Wide World Importers sample database once, then exit.
# Connection settings come from the compose environment (POSTGRES_*).
set -eu

DB="${SAMPLE_DATABASE:-wideworldimporters}"

if python /check_seeded.py "$DB"; then
  echo "sample-data: '$DB' is already loaded; nothing to do."
else
  echo "sample-data: loading '$DB' (about 2.2 million rows, usually under a minute)..."
  # --drop makes a previous partial load safe to retry. It only drops this one database.
  python /eval/scripts/seed/seed_wwi.py --database-name "$DB" --drop
fi

# Optional: start the semantic compilation without a click in Settings.
# Off by default because compilation makes many model calls (about 22 minutes
# on the sample), so it should be a deliberate choice: SAMPLE_AUTO_COMPILE=true
if [ "${SAMPLE_AUTO_COMPILE:-false}" = "true" ]; then
  python /enable_compile.py \
    || echo "sample-data: WARNING - turn it on yourself in Settings -> Semantic Compilation."
else
  echo "sample-data: semantic compilation stays OFF until you enable it in Settings -> Semantic Compilation"
  echo "             (or set SAMPLE_AUTO_COMPILE=true in .env to start it automatically)."
fi

# Show the suggested questions in the container log: docker compose logs sample-data
cat /questions.txt
