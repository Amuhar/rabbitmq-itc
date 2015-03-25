-module(rabbitmq_log).

-include_lib("include/rabbit_itc.hrl").
-compile([export_all]).
-define(FileName, "itc_stamps.log").

log(Record) ->
     case  file:open(?FileName, [append]) of
       {ok, Io} ->  
            Fmt = "id: ~s~n~n"
                  "Message type : ~s~n~n"
                  "Node : ~s~n~n"
                  "Exchange: ~s~n~n" ++
		   case Record#log_record.queue of 
			     none -> "";
			        _ -> "Queue: ~s~n~n"
		    end ++
		   "User name: ~s~n~n"
		   "Routing key : ~s~n~n"
		   "Payload : ~s~n~n"
                   "Interval tree clock stamp : ~s ~n~n " 
                   "Virtual host: ~s~n"
                   "Connection: ~s~n Channel: ~p~n"
                   "Properties: ~p~n"
                   "Binding: ~s~n~n",	
              Stamp = Record#log_record.stamp,
              Stamp_print = lists:flatten(io_lib:format("~p", [Stamp])),   
            
	      Args = [ list_to_binary(integer_to_list(Record#log_record.id)),
                       Record#log_record.type,
                       Record#log_record.node,
                       Record#log_record.exchange]++
                       case Record#log_record.queue of
                                        none -> [];
                                          Q -> [Q]
                       end ++
                      [
                        Record#log_record.username, Record#log_record.routing_keys,
                        Record#log_record.payload ,Stamp_print, Record#log_record.vhost,
                        Record#log_record.connection,Record#log_record.channel,
                        Record#log_record.properties,
                        lists:flatten(io_lib:format("~p", [Record#log_record.exchange_bindings]))],
                      
	      Data = io_lib:format(Fmt,Args),
              file:write(Io,Data),
              file:close(Io);   
        {error, Reason} ->
            io:format("~s open error  reason:~s~n", [?FileName, Reason]) %% хорошо бы подумать об обработке всех ошибок
        end.
