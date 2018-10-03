#!/bin/sh

COMMIT="`git $@ log --pretty=format:'%h' -n 1 2>/dev/null || echo '<no_commit>'`"
TAG="`git $@ describe --tags --exact-match 2>/dev/null || echo '<no_tag>'`"

cat > config/initializers/revision.rb << EOF
module Pompa
  COMMIT = '$COMMIT'
  TAG = '$TAG'
end
EOF
