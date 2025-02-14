FROM node:18.12.1-alpine AS node
FROM ruby:3.1.2-alpine AS base
FROM base AS builder

ENV RAILS_ENV production
ENV NODE_ENV production

# build for musl-libc, not glibc (see https://github.com/sparklemotion/nokogiri/issues/2075, https://github.com/rubygems/rubygems/issues/3174)
ENV BUNDLE_FORCE_RUBY_PLATFORM 1

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node /opt/yarn-* /opt/yarn

RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm  \
  && ln -s /opt/yarn/bin/yarn /usr/local/bin/yarn

RUN apk add --no-cache tzdata postgresql-dev build-base

WORKDIR /app

COPY Gemfile* /app/

RUN bundle config --local without 'development test' \
  && bundle install -j4 --retry 3 \
  && bundle clean --force \
  && rm -rf /usr/local/bundle/cache \
  && find /usr/local/bundle/gems/ -name "*.c" -delete \
  && find /usr/local/bundle/gems/ -name "*.o" -delete

COPY . /app

RUN bundle exec rails assets:precompile SECRET_KEY_BASE=fake_secure_for_compile \
  && yarn cache clean \
  && rm -rf node_modules tmp/cache/* /tmp/* yarn.lock log/production.log app/javascript/* app/assets/*


FROM base

ENV LANG C.UTF-8
ENV RAILS_ENV production
ENV RAILS_SERVE_STATIC_FILES true

RUN apk add --no-cache \
  tzdata \
  postgresql-dev \
  imagemagick \
  ffmpeg

WORKDIR /app

EXPOSE 3000

RUN addgroup -g 1000 -S app && adduser -u 1000 -S app -G app

COPY --from=builder --chown=app:app /usr/local/bundle/ /usr/local/bundle/
COPY --from=builder --chown=app:app /app/ /app/

USER app

ENTRYPOINT ["docker/entrypoint.sh"]

CMD ["docker/production_start.sh"]
