-record(log_record,
                   {id,type, exchange, queue, node, connection,channel,
		     vhost, username, routing_keys,properties,payload,stamp,exchange_bindings }). 
