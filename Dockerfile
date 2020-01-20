FROM ubuntu AS builder

# Ruby
RUN apt-get -y update
RUN apt-get -y install ruby ruby-dev build-essential nodejs

# Jekyll
RUN gem install bundler
RUN gem update --system

# Environment
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

# Gems
WORKDIR /src/jekyll-site
ADD Gemfile /src/jekyll-site/
ADD Gemfile.lock /src/jekyll-site/
RUN bundle install

ADD . /src/jekyll-site
RUN bundle exec jekyll build

FROM nginx
COPY --from=builder /src/jekyll-site/_site/ /usr/share/nginx/html/
COPY ./nginx/ /etc/nginx/conf.d/
