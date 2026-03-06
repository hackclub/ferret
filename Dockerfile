FROM ruby:3.3-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends libgomp1 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

COPY . .
RUN chmod +x bin/*

RUN mkdir -p data

EXPOSE 4567

CMD ["bundle", "exec", "ruby", "app.rb"]