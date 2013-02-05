#This module is for Toplevel Objects that are intended for storage in redis, with possible nested subobjects that are not meant to be
#stored independently in redis.

# So a Battle is a Toplevel Object. Video is not - it's always nested in redis, so it's just normal. Video does not include this
#module, but Battle would. A Toplevel Object should not reference another Toplevel Object via an association, but if it must, do not
#put it in the associations_names method so that this Toplevel object doesnt try to store it. That's what this module uses
# to determine associations with.
module RedisStorageMethods

  module ClassMethods
    def redis
      unless @redis
        @redis ||= Redis.new( :driver => :hiredis,
          :host => ENV['redis_host'], 
          :port => ENV['redis_port'])
          @redis.auth(ENV['redis_auth']) if ENV['redis_auth']
      end
      
      @tries = 0 unless @tries
      
      begin
        @redis.get("test") #tests to see if we're still authed.
        @tries = 0 #means we can reset our trymeter.
      rescue Exception => e
        @tries+=1 if @tries
        if @tries<5
          @redis = nil
          redis #reset it up.
        end
      end
      
      return @redis
    end 
    
    #if an object is passed as params, we know we're only putting this in redis, it already exists in db
    #if params is a hash, know we're creating in both.
    def create_with_associations_and_redis(params=nil)
      params = sanitize_all(params)
      if params.is_a?(Hash)
        if params.keys.select{ |k| k if k.to_s.match(/_attributes$/) }.size>0
          associations = remove_and_return_associations_hash!(params) 
          me = self.create(params)
          raise "Invalid #{me.class}: #{me.errors[me.errors.keys.first].first}" unless me.valid?
          me.create_associations_from_params(associations)
        else
          me = self.create(params) # if submits as normal form, not AR form.
          raise "Invalid #{me.class}: #{me.errors[me.errors.keys.first].first}" unless me.valid?
        end
      else
        me = params
      end

      redis.pipelined {
        redis.del("#{me.class.to_s.downcase}:#{me.id}") #overwrite it, make sure.
        redis.hmset("#{me.class.to_s.downcase}:#{me.id}", me.assemble_key_value_array_for_redis)
        redis.sadd("#{me.class.to_s.downcase.pluralize}", me.id)
        me.create_custom_redis_fields
      }
      
      me.after_redis_create_do
      return me
    end

    def sanitize_all(params)
      #below sanitizes all top level inputs
      return nil unless params
      to_ret = nil
      if params.is_a?(Hash)
        to_ret =  params.inject(Hash.new){ |hash, entry| hash[entry[0]] = entry[1].is_a?(String) ? Sanitize.clean(entry[1]) : sanitize_all(entry[1]); hash}
      elsif params.is_a?(Array)
        to_ret =  params.inject(Array.new){ |arr, entry| arr << (entry.is_a?(String) ? Sanitize.clean(entry) : sanitize_all(entry)); arr}
      end
      return to_ret
    end
    
    #form submits with something like { "fields" => keys... "video_attributes" => { "0" => { "fields" => keys}}}
    #but DataMapper doesnt support nested form submission like active record, so we have to remove these
    #nestings and then handle them appropriately here..We use a class var that the class must set to know what
    #to pull out.
    def remove_and_return_associations_hash!(params)
      associations = Hash.new
      associations_names.each do |a|
        associations[a] = params.delete("#{a.singularize}_attributes")
      end
      associations
    end
    
    #returns all redis stored objects
    def all_redis
      selfs = []
      redis.smembers(self.to_s.downcase.pluralize).each do |id|
        selfs << self.find_with_redis(id)
      end
      selfs
    end
  
    #populates a model with redis hash
    #note you cannot write with this guy, it won't let you
    #even though all the fields are set. 
    def find_with_redis(id)
      me = self.new
      redis_attr = redis.hgetall("#{me.class.to_s.downcase}:#{id}")
      return nil unless redis_attr["id"]
      me.attributes = redis_attr.reject { |field| field.match(/^\w+\d+\w+$/) or field.match(/^\w+_.*_\w+$/)}
      me.populate_associations_from_redis(redis_attr.select { |field| field.match(/\w+\d\w+/)})
      me.populate_custom_fields_from_extraneous_redis_calls
      me 
    end
    
    #should never get called by client, is method for cronjob to update db.
    def sync_all_with_redis
      self.all.each do |o|
        o.sync_with_redis
      end
    end
    
    #emergency method if redis db was lost, repopulate associations and stuff.
    def put_all_in_redis
      self.all.each do |a|
        a.put_in_redis
      end
    end

    #implementable
    
    # ["videos", "user", ...] plural if an array, singular if a has_one/belongs_to.
    def associations_names
      raise 'Must be implemented in object class'
    end
    
  end
 
  def self.included(base)
    base.extend ClassMethods
  end  

  #instance methods
  
  #must also define redis down here so it gets set,
  #there is an instance on the class object and instances of it then.
  def redis
    @redis ||= self.class.redis   
  end 

  def assemble_key_value_array_for_redis
    a = Array.new
    self.class.properties.map { |prop| prop.name.to_s }.each do |p|
      if(self.send(p)) 
        #this if statement is so nil values wont be stored as "" in redis 
        #and come back as an empty string, they will come back as nil.
        a<<p
        a<<self.send(p)
      end
    end
    self.add_key_value_pairs_of_associations_for_redis!(a)
    a
  end
  
  def destroy_with_redis
    self.destroy
    redis.del("#{self.class.to_s.downcase}:#{self.id}")
  end
  
  #this is a helper method that will construct objects from redis that have no
  #nested associations themselves. So we can keep code DRY. If you have nesting,
  #you must do it yourself.
  def construct_low_level_model_from_redis_hash(redis_hash, association)
      found = true
      i = 0
      while(found) do 
        if redis_hash["#{association.singularize}#{i}id"]
          params_hash = {}
      
          redis_hash.select {|k, v| k.to_s.match(/#{association.singularize}#{i}/)}.each do |key, value|
            params_hash[key.to_s.match(/#{association.singularize}#{i}(\w+)/)[1]] = value
          end
          
          self.send(association)<< Kernel.const_get(association.singularize.capitalize).new(params_hash)
        else
          found = false and break
        end
        i+=1
      end
  end
  
  #if the db object exists but needs to be placed in redis
  def put_in_redis
    self.class.create_with_associations_and_redis(self)
  end
  
  #implementable
  
  #accepts the part of the form hash with nested atributes(but with attributes taken off keys), like { "videos" => {"0" => {field => value}}}
  #and then creates models. Because we don't support nested creation at the meta level, must be handled locally.
  def create_associations_from_params(params)
    raise 'Must be implemented by the object class!'
  end
  
  #No nesting in Redis, no methods for listing associations on DataMapper, This is custom, returns nested objects for use in storage
  #with redis. Because I dont want to write metacode that detects nested objects within my own nested objects, I'm just leaving it
  # to each model to implement this in a custom fashion.
  def add_key_value_pairs_of_associations_for_redis!(array)
    raise 'Must be implemented by object class!'
  end

  #expects to get hash of things like video0video_id => "555" from redis, needs to create associations from it.
  def populate_associations_from_redis(redis_hash)
    raise 'Must be implemented by object class!'
  end
  
  #if you have sets stored outside the redis hash, need to make a call to get them, haven't you?
  # you can do that here, or leave this a nil method. It won't hurt you.
  def populate_custom_fields_from_extraneous_redis_calls
  end
  
  #method to sync object in db with redis.
  def sync_with_redis
    raise 'Must be implemented by object class!'
  end
  
  #create the custom fields you need like lists for arrays etc, artist:name => id references,
  #stuff like that.
  def create_custom_redis_fields
  end
  
  def after_redis_create_do
  end
end
