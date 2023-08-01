set dotenv-load := true

alias release := deploy
alias promote := deploy
# Serve containers locally
serve env='local':
    docker compose -f docker-compose.yml -f "docker-compose.{{env}}.yml" up

# Build containers
build env='ci':
    docker compose -f docker-compose.yml -f "docker-compose.{{env}}.yml" build

# Push containers to the registry
push env='ci':
    docker compose -f docker-compose.yml -f "docker-compose.{{env}}.yml" push

# Push containers to the registry
config env='prod':
    docker compose -f docker-compose.yml -f "docker-compose.{{env}}.yml" config

install:
    bundle install

watch:
    bundle exec jekyll serve

deploy env='staging':
    git branch -f {{env}} main
    git push origin {{env}}
