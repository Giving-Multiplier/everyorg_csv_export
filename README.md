# Every.org donation CSV export
Ruby script that logs into every.org and download the every.org donation csv.
* Using a headless chrome session as it needs javascript
* Option to upload it to an endpoint for further processing

## Setup

1. Install ruby 3.4
2. Install Chrome
3. Run `bundle` to install ruby gems
4. Setup env variables (see .env.examples)

## Run

1. Run `rake`


## Deployment

Deploy to heroku by
1. Creating a new project on heroku
2. Add env variables to settings
3. Add buildpack `https://buildpack-registry.s3.amazonaws.com/buildpacks/heroku-community/chrome-for-testing.tgz`
4. Push to heroku
5. Run `rake`

For regular runs setup [a scheduler](https://devcenter.heroku.com/articles/scheduler)
