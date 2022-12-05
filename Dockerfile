FROM ruby:2.7-buster AS builder

# Install deps
RUN apt-get -y update && \
    apt-get -y install build-essential nodejs

# Install bundler
RUN gem install bundler && gem update --system

# Environment
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# Gems
WORKDIR /srv/jekyll/
ADD Gemfile /srv/jekyll/
ADD Gemfile.lock /srv/jekyll/
RUN bundle install


ARG JEKYLL_ENV=production
ADD . /srv/jekyll
RUN bundle exec jekyll build

FROM nginx
LABEL org.opencontainers.image.source https://github.com/alexrudy/alexrudy.net
COPY --from=builder /srv/jekyll/_site/ /usr/share/nginx/html/
COPY ./nginx/ /etc/nginx/conf.d/
