# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"

require "azure"

class LogStash::Inputs::AzureTableMulti < LogStash::Inputs::Base
  class Interrupted < StandardError; end

  config_name "azuretablemulti"
  milestone 1
  
  config :account_name, :validate => :string
  config :access_key, :validate => :string
  config :table_name, :validate => :string
  config :entity_count_to_process, :validate => :string, :default => 100
  config :collection_start_time_utc, :validate => :string
  config :etw_pretty_print, :validate => :boolean, :default => false
  config :idle_delay_seconds, :validate => :number, :default => 5
  config :endpoint, :validate => :string, :default => "core.windows.net"
  config :reversetimestamp, :validate => :boolean, :default => false

  TICKS_SINCE_EPOCH = Time.utc(0001, 01, 01).to_i * 10000000


  def initialize(*args)
    super(*args)
  end # initialize


  public
  def register
    Azure.configure do |config|
      config.storage_account_name = @account_name
      config.storage_access_key = @access_key
      config.storage_table_host = "https://#{@account_name}.table.#{@endpoint}"
    end
    @azure_table_service = Azure::Table::TableService.new
    @continuation_token = nil

    # Check if collection time was provided
    # TODO: Check if not empty - to take into consideration
    @collection_start_time_utc = (Time.now.utc - 3*60).iso8601 #Time.now.utc.iso8601

    @pkey_start = -1
    @pkey_end = -1
    # Compute the date from collection_start_time_utc
    if @reversetimestamp
        @pkey_start = partitionkey_from_datetime_reverse(@collection_start_time_utc)
    else
        @pkey_start = partitionkey_from_datetime(@collection_start_time_utc)
    end
  end # register

  
  public
  def run(output_queue)
    while !stop?
      @logger.info("[#{@table_name}] Process re-executed @" + Time.now.to_s);
      process(output_queue)
      sleep @idle_delay_seconds
    end # while
  end # run

 
  public
  def teardown
  end  


  def process(output_queue)
    # # # # # #
    # Construct query (pkey_end is always 3 minutes back)
    # If continuation token exists then use the same query
    if @reversetimestamp
       @pkey_end = partitionkey_from_datetime_reverse( (Time.now.utc - 3*60).iso8601 )
       @logger.info("[#{@table_name}] Query starts: #{datetime_from_partitionkey_reverse(@pkey_start)} and ends #{datetime_from_partitionkey_reverse(@pkey_end)}")
       query_filter = "(PartitionKey lt '#{@pkey_start}9999999' and PartitionKey ge '#{@pkey_end}9999999')"
    else
       @pkey_end = partitionkey_from_datetime( (Time.now.utc - 3*60).iso8601 )
       @logger.info("[#{@table_name}] Query starts: #{datetime_from_partitionkey(@pkey_start)} and ends #{datetime_from_partitionkey(@pkey_end)}")
       query_filter = "(PartitionKey gt '0#{@pkey_start}' and PartitionKey le '0#{@pkey_end}')"
       if @table_name == "LinuxsyslogVer2v0"
          for i in 0..99
            query_filter << " or (PartitionKey gt '#{i.to_s.rjust(19, '0')}___0#{@pkey_start}' and PartitionKey lt '#{i.to_s.rjust(19, '0')}___0#{@pkey_end}')"
          end # for block
       end
    end
    query_filter = query_filter.gsub('"','')
    @logger.info("[#{@table_name}] Query filter: " + query_filter)

    # # # # #
    # Execute until the continuation data is empty
    begin
       # Perform the query
       query = { :top => @entity_count_to_process, :filter => query_filter, :continuation_token => @continuation_token }
       result = @azure_table_service.query_entities(@table_name, query)
       @continuation_token = result.continuation_token
       # If results
       if result and result.length > 0
          @logger.info("[#{@table_name}] Retrieved #{result.length} entries. Continuation: #{@continuation_token}")
          # Iteration through all and send
          result.each do |entity|
             if @reversetimestamp
                event = LogStash::Event.new( { "PartitionKey"=>entity.properties["PartitionKey"], "RowKey"=>entity.properties["RowKey"], "Payload"=>entity.properties["Payload"], "EventDate"=>"#{entity.properties["EventDate"]}" } )
             else
                event = LogStash::Event.new(entity.properties)
             end
             event.set("table_name" , @table_name)
             decorate(event)
             output_queue << event
          end # each block
          # Compute the new start data for next query (the Max minimum)
          if @reversetimestamp
             if result.last.properties["PartitionKey"][0,12].to_i < @pkey_start
                @pkey_start = result.last.properties["PartitionKey"][0,12].to_i
             end
          else
             if @table_name == "LinuxsyslogVer2v0"
                if result.last.properties["PartitionKey"][23,41].to_i > @pkey_start
                   @pkey_start = result.last.properties["PartitionKey"][23,41].to_i
                end
             else
                if result.last.properties["PartitionKey"][1,19].to_i > @pkey_start
                   @pkey_start = result.last.properties["PartitionKey"][1,19].to_i
                end
             end 
          end
       # If no results
       else
          @logger.info("[#{@table_name}] No new results found.")
       end
       # Sleep a bit if continuation loop is going to happen
       if !@continuation_token.nil?
          @logger.info("[#{@table_name}] Continuation will be performed")
          sleep 1
       end 
    end until @continuation_token.nil?
    
  rescue => e
    @logger.error("[#{@table_name}] Oh My, An error occurred.", :exception => e)
    raise
  end # process


  # Windows Azure Diagnostic's algorithm for determining the partition key based on time is as follows:
  # 1. Take time in UTC without seconds.
  # 2. Convert it into .net ticks
  # 3. add a '0' prefix.
  def partitionkey_from_datetime(time_string)
    collection_time = Time.parse(time_string)
    if collection_time
      @logger.debug("[#{@table_name}] Collection time parsed: #{collection_time}")
    else
      raise(ArgumentError, "Could not parse the time_string")
    end # if else block
    collection_time -= collection_time.sec
    return collection_time.to_i * 10000000 - TICKS_SINCE_EPOCH
  end # partitionkey_from_datetime

  def datetime_from_partitionkey(pkey)
    collection_time = (pkey + TICKS_SINCE_EPOCH) / 10000000
    return Time.at(collection_time).to_datetime
  end

  # Dot net algorithm for determining the partition key based on time is as follows:
  # 1. Take time in UTC without seconds.
  # 2. Convert it into .net ticks
  # 3. add a '0' prefix.
  def partitionkey_from_datetime_reverse(time_string)
    collection_time = Time.parse(time_string)
    if collection_time
      @logger.debug("[#{@table_name}] Reverse collection time parsed: #{collection_time}")
    else
      raise(ArgumentError, "Could not parse the time_string")
    end # if else block
    collection_time -= collection_time.sec
    return 253402300799 - collection_time.to_i
  end # partitionkey_from_datetime_reverse
  
  def datetime_from_partitionkey_reverse(pkey)
    collection_time = 253402300799 - pkey
    return Time.at(collection_time).to_datetime
  end


end # LogStash::Inputs::AzureTableMulti
