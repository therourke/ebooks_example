# boodoo_ebooks

A turn-key, beginner-friendly, ready-to-deploy implementation of a traditional \_ebooks bot using Mispy's [twitter_ebooks](https://github.com/mispy/twitter_ebooks) library.

## Usage

Create your [Twitter app](https://apps.twitter.com) and generate access tokens with *Read, Write and Direct Messages* privileges.

### Deploy with no Papertrail addon [no card required]

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy?template=https://github.com/BooDoo/ebooks_example/tree/deploy)

### Deploy using Papertrail for online logs
#### [Valid Credit Card required, but free to use]

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy?template=https://github.com/BooDoo/ebooks_example/tree/deploy-no-card)

### Deploy using Papertrail and Cloudinary for persistent files
#### [Valid Credit Card required, but free to use]

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy?template=https://github.com/BooDoo/ebooks_example/tree/persist-cloudinary)

Put your BOT_NAME, SOURCE_USERNAME, and API secrets into Heroku Config Vars using the web dashboard.

*IF USING CLOUDINARY:* Optionally set the filename of starting corpus (`tweets.csv`, an ebooks json archive, or a plaintext file) and upload via Cloudinary dashboard.

Scale your app to 1 dyno using the Heroku web dashboard.

Bob's your uncle.

## Default Behavior
Tweets once on startup.  
Has 80% chance of tweeting every 2 hours.  
Responds to mentions/DMs  
Favorites tweets that it likes.

## Special Features
- **BLACKLIST**: accounts to not interact with  
- **BANNED_TERMS**: words or phrases to obscure/censor  
- DM commands (tweet, follow, unfollow, block, mention...)  
- Follower parity (periodically compares following/followers and follows/unfollows as needed)  
- Want something else? Create an [issue](https://github.com/BooDoo/ebooks_example/issues). No promises.

## TODO:
- This is a mess and needs a total rewrite with actual design  

# DISCLAIMER:
I'm making this because I wrote a two-part tutorial for an older version of the twitter_ebooks gem and my mentions turned into a tech support hellscape for months.  
Please [create issues](https://github.com/BooDoo/ebooks_example/issues) if you have trouble. 🙏 Please do not tweet at me. 🙏
