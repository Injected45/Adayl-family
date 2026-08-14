#!/usr/bin/env bash
# Runs the app against the live Supabase project.
#
# The URL and the anon/publishable key are NOT secrets — they ship inside every
# build of this app and can be read out of the web bundle. Keeping them in a
# checked-in script is fine and saves retyping them.
#
# The SERVICE ROLE key is a different thing entirely: it bypasses RLS. It must
# never appear here, in a --dart-define, or in any file the app is built from.
#
#   bash run_supabase.sh            # chrome
#   bash run_supabase.sh windows    # or any other device id
set -euo pipefail

DEVICE="${1:-chrome}"

SUPABASE_URL="https://wvryyidbjvvomurvfhpw.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind2cnl5aWRianZ2b211cnZmaHB3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3MjgzMzgsImV4cCI6MjEwMjMwNDMzOH0.ZvppQmbFK_mU-XWocTFqc9zIUW0CTb9lctD_9yuZ8nk"

exec flutter run -d "$DEVICE" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  "${@:2}"
