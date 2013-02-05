# RedisStorageMethods

RedisStorageMethods allows you to include a MixIn to your models that will let you easily create copies in a redis store when you create actual objects with no extra logic, and expose methods that enable you to find in redis store, not in the database, to protect yourself from the massive time costs in querying with SQL compared to Redis.

## Installation

Add this line to your application's Gemfile:

    gem 'redis_storage_methods'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install redis_storage_methods

## Usage

Pretty easy here, just do:

    class Battle < ActiveRecord::Base
      include RedisStorageMethods
      ...
    end

Once you've done this, you'll need to add a few methods to Battle that the Mixin requires to be defined(even empty methods will do).

    #accepts the part of the form hash with nested atributes(but with attributes taken off keys), like { "videos" => {"0" => {field => value}}}
    #and then creates models. Because we don't support nested creation at the meta level, must be handled locally.
    def create_associations_from_params(params)
    end
    
    #No nesting in Redis, no methods for listing associations on DataMapper/AR, This is custom, returns nested objects for use in storage
    #with redis. Because I dont want to write metacode that detects nested objects within my own nested objects, I'm just leaving it
    # to each model to implement this in a custom fashion.
    def add_key_value_pairs_of_associations_for_redis!(array)
    end
  
    #expects to get hash of things like video0video_id => "555" from redis, needs to create associations from it.
    def populate_associations_from_redis(redis_hash)
    end
    
    #if you have sets stored outside the redis hash, need to make a call to get them, haven't you?
    # you can do that here, or leave this a nil method. It won't hurt you.
    def populate_custom_fields_from_extraneous_redis_calls
    end
    
    #method to sync object in db with redis.
    def sync_with_redis
    end
    
    #create the custom fields you need like lists for arrays etc, artist:name => id references,
    #stuff like that.
    def create_custom_redis_fields
    end
    
    def after_redis_create_do
    end

  Copy and paste these bad boys into the Battle class. You should be aware that nested associations are not stored in redis by default, most of these methods involve implementing them to allow for nesting.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
