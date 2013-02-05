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

Presumably, you'll be passing hashes into your create method. Now you will need to pass them into your
  
    create_with_associations_and_redis(params)

method. This is to differentiate between the two: This method will take your object and create it, and then store it in redis as a hash. It will not store it's associations unless you instruct it to do so. This is because redis has no ability to store foreign keyed objects, if a Battle has a Soldier in it, you can really only store it in a redis hash for Battle like this: soldier0hp, soldier0stamina, soldier1hp, soldier1stamina, etc.

You need to instruct it to do this.
 
Pretty easy here, just do:

    class Battle < ActiveRecord::Base
      include RedisStorageMethods
      has_many :soldiers
      ...
    end

Once you've done this, you'll need to add a few methods to Battle that the Mixin requires if you want to store nested objects, like Soldiers for a battle. I am going to provide an example set of methods below assuming Battle has a nested object called Soldier.

    #accepts the part of the form hash with nested atributes(but with attributes taken off keys), like { "soldiers" => {"0" => {field => value}}}
    #and then creates models. Because we don't support nested creation at the meta level, must be handled locally.
    def create_associations_from_params(params)
      params["soldiers"].andand.each do |index, values|
        self.soldiers << Soldier.create(values.merge("battle_id" => self.id))
      end
    end
    
    #No nesting in Redis, no methods for listing associations on DataMapper/AR, This is custom, returns nested objects for use in storage
    #with redis. Because I dont want to write metacode that detects nested objects within my own nested objects, I'm just leaving it
    # to each model to implement this in a custom fashion.
    def add_key_value_pairs_of_associations_for_redis!(array)
      i=0
      soldiers.each do |video|
        Soldier.properties.map { |prop| prop.name.to_s }.each do |p|
          array<<"soldier#{i}#{p}"
          array<< soldier.send(p)
        end
        i+=1
      end

      array
    end
  
    #expects to get hash of things like video0video_id => "555" from redis, needs to create associations from it. This is used when we GET from Redis, and need to reconstruct a model.
    def populate_associations_from_redis(redis_hash)
      construct_low_level_model_from_redis_hash(redis_hash, "soldiers")
      #bonus, this method above is included in RedisStorageMethods for simple models that have no 
      #other associations and only attribute values. It will take fields like "soldier0hp", realize
      #it's part of a soldier object, the zeroth in the index, and make that soldier.

    end
    
    #if you have sets stored outside the redis hash, need to make a call to get them, haven't you?
    # you can do that here, or leave this a nil method. It won't hurt you.
    def populate_custom_fields_from_extraneous_redis_calls
    end
    
    #method to sync object in db with redis. You may want to set this up on a cron script to keep
    #the databases in sync. A lot of developers don't want to call the DB for PUT requests, they
    #just find & change the redis object instead. This is where you reconcile
    def sync_with_redis
      me_fake = Battle.find_with_redis(self.id)
      
      self.soldiers.each do |soldier|
        me_fake.soldiers.each do |f_s|
          soldier.hp = f_s.hp if(soldier.id == f_s.id)
        end
      end
      
      self.save

    end
    
    #create the custom fields you need like lists for arrays etc, artist:name => id references,
    #stuff like that.
    def create_custom_redis_fields
    end
    
    #after hook for after you put hash in redis.
    def after_redis_create_do
    end

  Copy and paste these bad boys into the Battle class. You should be aware that nested associations are not stored in redis by default, most of these methods involve implementing them to allow for nesting.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
