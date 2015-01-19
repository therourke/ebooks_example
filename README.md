# mu_ebooks

I'M SORRY IT'S COME TO THIS

## Usage

Click this:  
[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy?template=https://github.com/BooDoo/ebooks_example/tree/robinbot)

Put your API secrets into Heroku Config Vars using the web dashboard.

Scale your app to 1 dyno using the Heroku web dashboard.

You're ready to go.

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
