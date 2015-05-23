-module(rabbitmq_itc).

-include_lib("amqp_client/include/amqp_client.hrl").
-include_lib("stdlib/include/qlc.hrl").
-include_lib("include/rabbit_itc.hrl").

-behaviour(gen_server).

-compile([export_all]).

-rabbit_boot_step({rabbit_itc__mnesia,
	[{description, "rabbitmq interval tree clock: mnesia"},
	{mfa, {?MODULE, setup_schema, []}},
        {cleanup, {?MODULE, disable_plugin, []}},
	{requires, database},
	{enables, external_infrastructure}]}).

-define(ITC_TABLE, itc_table).
-define(X, <<"amq.rabbitmq.trace">>).
-define(Err,<<"Out-of-bounds indeces in Mnesia table">>). %%  если индексы запрашиваемой цепочки выходят за границы

-record(state, {conn, ch,queue,stamp}).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_link([]) -> 
   gen_server:start_link({local,?MODULE},?MODULE, [], []).


init(Args) ->
    {ok, Conn} = amqp_connection:start( #amqp_params_network{}),
    link(Conn),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    link(Ch),
    #'queue.declare_ok'{queue = Q} =
        amqp_channel:call(Ch, #'queue.declare'{durable   = false, exclusive = true}),
    #'queue.bind_ok'{} =
    amqp_channel:call(
      Ch, #'queue.bind'{exchange = ?X, queue = Q,
                        routing_key = <<"#">>}),
    #'basic.qos_ok'{} =
        amqp_channel:call(Ch, #'basic.qos'{prefetch_count = 10}),
    #'basic.consume_ok'{} =
        amqp_channel:subscribe(Ch, #'basic.consume'{queue  = Q,no_ack = false}, self()),
  
    {ok, #state{conn = Conn, ch = Ch, queue = Q,stamp = itc:seed()} }.

handle_call(all,_From,State) ->
  ListRec = all_table(),
  {reply,ListRec,State};

handle_call({chain,F,T},_From,State) ->
  D = lists:seq(1,mnesia:table_info(?ITC_TABLE,size)),
  C = lists:member(F,D) and lists:member(T,D) and (F /= T), 
  ListRec =  
  case C of
    true -> event_chain(F,T);
    _ -> [?Err]
  end,
  {reply,ListRec,State};
  

handle_call(_Req, _From, State) ->
    {reply, unknown_request, State}.

handle_info(Delivery = {#'basic.deliver'{delivery_tag = Seq}, #amqp_msg{}},
            State = #state{ch = Ch}) ->
    New_state = header_information(Delivery, State),
    amqp_channel:cast(Ch, #'basic.ack'{delivery_tag = Seq}),
    {noreply, New_state};

handle_info(I, State) ->
    {noreply, State}.

terminate(shutdown, _State = #state{conn = Conn, ch = Ch}) ->
     catch amqp_channel:close(Ch),
     catch amqp_connection:close(Conn),
    ok;
terminate(_Reason, _State) ->
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%% Работа с БД

all() ->
    gen_server:call(?MODULE, all, infinity).

chain({From,To}) ->
    gen_server:call(?MODULE,{chain,From,To},infinity).
  

setup_schema() ->
	mnesia:create_table(?ITC_TABLE,
	[{attributes, record_info(fields, log_record)},
	{record_name, log_record},
	{type,  ordered_set}]),
	mnesia:add_table_copy(?ITC_TABLE, node(), ram_copies),
	mnesia:wait_for_tables([?ITC_TABLE], 30000),
	ok.

disable_plugin() ->
	mnesia:delete_table(?ITC_TABLE),
	ok.

%% определить в другой модуль
do(Q) ->
    F = fun() -> qlc:e(Q) end,
    {atomic, Val} = mnesia:transaction(F),
    
    Val.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% получение всей таблицы

all_table() -> 
Records = do(qlc:q([X|| X <- mnesia:table(?ITC_TABLE)])),
lists:map( fun(X) ->
            [ if I == tuple_size(X) -1 -> 
                  list_to_binary(lists:flatten(io_lib:format("~p", [element(I,X)])));
                 true -> 
                  element(I,X)
              end ||I <- lists:seq(2,tuple_size(X) -1 )] end,Records).

%% получение цепочки событий 

event_chain(F_id,T_id) ->
  [F,T] = do(qlc:q([X || X <- mnesia:table(?ITC_TABLE), X#log_record.id == F_id orelse X#log_record.id == T_id])),
  Comp = [itc:leq(F#log_record.stamp,T#log_record.stamp), itc:leq(T#log_record.stamp,F#log_record.stamp)],
  case Comp of
    [true, true]  -> [<<"Events are equivalent">>];
    [false,false] -> [<<"Events are concurrent">>];
    _ -> 
      Records = do(qlc:q([X|| X <- mnesia:table(?ITC_TABLE),
      itc:leq(X#log_record.stamp, T#log_record.stamp) andalso
      itc:leq(F#log_record.stamp,X#log_record.stamp) andalso not
      itc:leq(X#log_record.stamp,F#log_record.stamp) andalso not
      itc:leq(T#log_record.stamp, X#log_record.stamp) orelse 
      X == F orelse X == T ])),
      ListRec = lists:map( fun(X) ->
                  [ if I == tuple_size(X) -1 -> 
                        list_to_binary(lists:flatten(io_lib:format("~p", [element(I,X)])));
                       true -> 
                        element(I,X)
                    end ||I <- lists:seq(2,tuple_size(X) -1 )] end,Records)

  end.

%%% Чтение информации из заголовка 

header_information(Delivery = { #'basic.deliver'{routing_key = Key,delivery_tag =D}, 
                       #amqp_msg{props = #'P_basic'{headers = H},payload = Payload}}, 
                       State = #state{conn = Conn, ch = Ch}) ->
         {Type, Q} = case Key of
                    <<"publish.", _Rest/binary>> -> {published, none};
                    <<"deliver.", Rest/binary>>  -> {received,  Rest}
                end,
          {longstr, Node} = rabbit_misc:table_lookup(H, <<"node">>),
          {longstr, X} = rabbit_misc:table_lookup(H, <<"exchange_name">>),
          {array, Keys} =rabbit_misc:table_lookup(H, <<"routing_keys">>),
          {table, Props} = rabbit_misc:table_lookup(H, <<"properties">>),
          {longstr, C} = rabbit_misc:table_lookup(H, <<"connection">>),
          {longstr, VHost} = rabbit_misc:table_lookup(H, <<"vhost">>),
          {longstr, User} = rabbit_misc:table_lookup(H, <<"user">>),
          {signedint, Chan} = rabbit_misc:table_lookup(H, <<"channel">>),
          {table, Props} = rabbit_misc:table_lookup(H, <<"properties">>),
	  Rec = #resource{virtual_host = VHost,
	      				name = X, kind = exchange},
          Bindings = rabbit_binding:list_for_source( Rec), 
          Size_of_table = mnesia:table_info(?ITC_TABLE,size),
 
          Record = #log_record{
                              id = Size_of_table +1, %% --
                              type = Type, %% --
                              exchange = X, %% +
                              queue = Q, %% --
                              node = Node, %% +
                              connection = C, %% +
                              vhost = VHost, %% ++
                              username = User, %% ++
                              routing_keys =[K || {_, K} <- Keys], %% ++
                              payload = Payload, %% --
                              channel = Chan, %% ++
                              properties = Props, %% ++
                              exchange_bindings = Bindings %% -- нужно , чтобы отфильтровать сообщения,  непрошедшие маршрутизацию
                             },     
   
       case Type of 
               published -> 
                           {New_record, New_state} = publish_message(Record,State),
                           rabbitmq_log:log(New_record),
                           New_state;
                       _ -> 
                             {New_record, New_state} = received_message(Record,State),
                             rabbitmq_log:log(New_record),
                             New_state
            end.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


publish_message(Record,State=#state{stamp = User_number}) ->
  {Update_record,New_state} = 
	 case mnesia:table_info(?ITC_TABLE,size) of 
			0 -> {New_stamp, User_stamp} = itc:fork(User_number),
                             Add_event_to_stamp = itc:event(User_stamp),
                             Update_record = Record#log_record{stamp = Add_event_to_stamp}, 
  			    
                            
                             {Update_record,State#state{ stamp = New_stamp} } ;
			N -> User_events  = do(qlc:q([X#log_record.stamp || X <- mnesia:table(?ITC_TABLE), 
		                   X#log_record.node == Record#log_record.node, 
		                   X#log_record.connection == Record#log_record.connection,
		                   X#log_record.channel == Record#log_record.channel,
		                   X#log_record.vhost == Record#log_record.vhost,
		                   X#log_record.username == Record#log_record.username])),
                       if 
                          User_events == [] -> 
                               {New_stamp, User_stamp} = itc:fork(User_number),
                               Add_event_to_stamp = itc:event(User_stamp), 
                               Update_record = Record#log_record{stamp = Add_event_to_stamp}, 
                               {Update_record,State#state{ stamp = New_stamp} } ;
                          true ->  
                               [Last|_Rest] = lists:reverse(User_events),
                               New_user_event = itc:event(Last),
                               Update_record = Record#log_record{stamp = New_user_event},
                               {Update_record,State}
                       end                  
   end,
  rabbit_misc:execute_mnesia_transaction(fun () -> mnesia:write(?ITC_TABLE,Update_record,write) end),		
  {Update_record,New_state}.


received_message(Record,State=#state{stamp = User_number }) -> 
  User_events  = 
    do(qlc:q([X || X <- mnesia:table(?ITC_TABLE), 
              X#log_record.node == Record#log_record.node, 
              X#log_record.connection == Record#log_record.connection,
              X#log_record.channel == Record#log_record.channel,
              X#log_record.vhost == Record#log_record.vhost,
              X#log_record.username == Record#log_record.username])),
      
  {ok,X} = rabbit_exchange:lookup(#resource{virtual_host = Record#log_record.vhost,
  				name = Record#log_record.exchange, kind = exchange}),
  Possible_produsers = 
    do(qlc:q([X || X <- mnesia:table(?ITC_TABLE), 
              X#log_record.exchange == Record#log_record.exchange, 
              X#log_record.payload == Record#log_record.payload,
              X#log_record.type == published, X#log_record.exchange_bindings /= []])), 
  {Mess_count, Last, New_stamp_state,Produsers} =                                  
  if 
    User_events == [] ->
      {New_stamp, User_stamp} = itc:fork(User_number),
      {0,User_stamp,New_stamp,Possible_produsers};                           
    true -> 
      {Consumers,Prod} =  
      if  X#exchange.type == fanout ->
          Same_consumers_mess = 
            lists:filter(fun(X) -> X#log_record.exchange == Record#log_record.exchange andalso
                          X#log_record.payload == Record#log_record.payload andalso
                          X#log_record.queue == Record#log_record.queue andalso
                          X#log_record.type == received end,User_events),  
          {Same_consumers_mess,Possible_produsers };
          
          X#exchange.type == direct orelse X#exchange.type == topic -> 
          
          Direct_or_topic_produsers = 
					 lists:filter(fun(X) ->
              hd(X#log_record.routing_keys) == hd(Record#log_record.routing_keys) end,Possible_produsers ), %% под вопросом
          Same_consumers_mess =
            lists:filter(fun(X) -> 
                                   X#log_record.exchange == Record#log_record.exchange andalso
                                   X#log_record.payload == Record#log_record.payload andalso
                                   X#log_record.queue == Record#log_record.queue andalso
                                   X#log_record.routing_keys == Record#log_record.routing_keys end, User_events),
          {Same_consumers_mess,Direct_or_topic_produsers}
    %%X#exchange.type == headers ->  что с этим делать не знаю                                    
      end,
      L = lists:last(User_events),
      {length(Consumers),L#log_record.stamp,none,Prod} 
  end,
  [Produser|_] = lists:nthtail(Mess_count, Produsers),
  {Event_for_join,Old_stamp} = itc:peek(Produser#log_record.stamp),
	Receive_message  = itc:join(Event_for_join,Last),
	New_event = itc:event(Receive_message),
        Update_record = Record#log_record{stamp = New_event},
	rabbit_misc:execute_mnesia_transaction(fun () -> mnesia:write(?ITC_TABLE,Update_record,write) end),
	case New_stamp_state of
		none -> 
			{ Update_record,State};
		_ ->
			{Update_record,State#state{stamp = New_stamp_state} }
				
	end.
