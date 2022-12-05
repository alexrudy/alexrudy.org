set dotenv-load := true

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

# Push the configuration to automoton
publish env='staging':
    just config {{env}} | automoton-client -e {{env}} configure alexrudy-net

install:
    bundle install

watch:
    bundle exec jekyll serve
