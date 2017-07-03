import std.stdio;
import std.conv;
import std.json;
import std.format;
import zmqd;
import vm;
//import zhelpers;
import core.time;
import std.concurrency;


void Server(Tid parentId)
{
  import std.file;
  VM vm = new VM();
  //read bytecode fie
  auto raw = cast(ubyte[])read("c:\\temp\\test.scur");
  int entry = 0;
  readProgram(vm.strings,vm.program,entry, raw );

  vm.machines ~= MachineStatus();
  writeln("program loaded: ", vm.program);
  vm.machines[0].callStack ~= StackFrame();
  vm.lastHeart = MonoTime.currTime;
  vm.zmqThread = parentId;
  vm.requiredPlayers = 2;
  vm.universe = new GameUniverse();

  GameObject state = new GameObject();
  state.id = -1;
  state.visibility = "";
  HeapVariant[string] players;
  state.props["players"] = new HeapVariant(players);
  vm.universe.objects[-1] = state;
  writeln("vm ready");
  
  // initally we process the machine startup until
  // it is ready 

  while(true)
    {    
      if(!receiveTimeout
         (
          dur!"msecs"(1),
          (ClientMessage message)
          {
            //                writeln("received message ", message);
            switch(message.type)
              {
              case MessageType.Connect:
                {
                  if( vm.ContainsPlayer(message.client))
                    {
                      writeln("client ", message.client, " reconnected");
                    }
                  else
                    {
                      if(vm.players.length < vm.requiredPlayers)
                        {
                          writeln("client ", message.client, " connected");
                          vm.AddPlayer(message.client);
                          if(vm.players.length == vm.requiredPlayers)
                            {
                              writeln(players);
                              writeln("game starting..");
                              while(!step(&vm) && !vm.finished)
                                {
                                  //                                  writeln("executing instruction..");
                                }
                              writeln(players);
                            }
                          else
                            {
                              writeln("waiting for ", vm.requiredPlayers - vm.players.length, " more plaers");
                            }
                        }
                      else
                        {
                          writeln("client ", message.client, " rejected. max players already");          
                        }                                                                   
                    }
                  break;
                }
              case MessageType.Heartbeat:
                {
                  vm.hearts[message.client] = MonoTime.currTime;
                  send(parentId,message);
                  break;
                }
              case  MessageType.Data:
                {
                  try
                    {
                      auto j = message.json.parseJSON;
                      switch(j["type"].str)
                        {
                        case "chat":
                          if(j["id"].str == "")
                            {
                              foreach(kvp; vm.players.byKeyValue)
                                {
                                  
                                  auto cm =
                                    ClientMessage
                                    (kvp.key,
                                     MessageType.Data,
                                     format("{\"type\":\"chat\",\"id\":\"%s\",\"msg\":\"[all][%s] %s\"}",
                                            kvp.key, kvp.key, message.json));
                                  parentId.send(cm);
                                }
                            }
                          else
                            {
                              if(j["id"].str in vm.players)
                                {
                                  auto id = j["id"].str;
                                  auto cm =
                                    ClientMessage
                                    (id,
                                     MessageType.Data,
                                     format("{\"type\":\"chat\",\"id\":\"%s\",\"msg\":\"[%s] %s\"}",
                                            id, id, message.json));
                                  //writeln("individual message ", cm);
                                  parentId.send(cm);
                                }
                              else
                                {
                                  writeln("! ", j["id"].str);
                                  auto cm =
                                    ClientMessage
                                    (message.client,
                                     MessageType.Data,
                                     "{\"type\":\"chat\",\"id\":\"server\",\"msg\":\"No player exists with that name. \"}");                         
                                  parentId.send(cm);                              
                                }
                            }
                          break;
                        case "response":
                          wdb("handling ...");
                          if(handleResponse(&vm,message.client,j))
                            {
                              while(!step(&vm))
                                {
                                  //                              writeln("executing instruction..");
                                }
                            }
                          // writeln("local vars:");
                          //writeln(vm.machines[0].currentFrame.locals);
                          break;
                                                    
                        default:
                          writeln("unknown json message ", message.json);
                          break;
                        }
                    }
                  catch( Exception e)
                    {
                      writeln("exception caught ", e);
                    }
                  break;
                }
              default:
                writeln("unexpceted!");
              } 
          },

          (Variant any) {writeln("unexpecged msg ", any);}))
        {
          if(MonoTime.currTime - vm.lastHeart > dur!"msecs"(100))
            {
              vm.lastHeart = MonoTime.currTime;
              foreach(kvp;vm.hearts.byKeyValue)
                {
                  if(MonoTime.currTime - kvp.value > dur!"seconds"(2))
                    {
                      writeln("client ", kvp.key, " has disconnected");
                    }
                }
            }          
        }
    }
}



void main()
{
  // Prepare our context and sockets
  auto server = Socket(SocketType.router);
  server.bind("tcp://*:5560");

  // Initialize poll set
  auto items = [
                PollItem(server, PollFlags.pollIn),
                ];
  writeln("spawning server...");
  auto worker = spawn(&Server, thisTid);
    
  // Switch messages between sockets
  while (true) {
    Frame frame;
    ClientMessage message;

    if(!receiveTimeout
       (dur!"msecs"(1),
        (ClientMessage msg)
        {
          server.send(msg.client,true);
          ubyte[] data = [cast(ubyte)msg.type];

          if(msg.type == MessageType.Data)
            {
              server.send(data,true);
              writeln("sending json ", msg.json);
              server.send(msg.json);
            }
          else
            {
              server.send(data);
            }

        },
          
        (Variant  any) { writeln("unexpected msg ", any);}
        ))
      {
        poll(items, dur!"msecs"(1));
        if (items[0].returnedEvents & PollFlags.pollIn) {            
          bool invalidMessage = false;
          /// first frame will be the id
          frame.rebuild();
          server.receive(frame);
          string client = frame.data.asString;
          //            writeln("identifier ", client);
          message.client = client.dup;
          if(frame.more)
            {
              frame.rebuild();
              server.receive(frame);
              // see what sort of message this is
              message.type = cast(MessageType)frame.data[0];
            }
          //            writeln("message type ", message.type);
          if(frame.more)
            {
              if(message.type == MessageType.Data)
                {
                  frame.rebuild();
                  server.receive(frame);
                  message.json = frame.data.asString.dup;
                  send(worker, message);
                  //                    writeln("sent message to worker ", message);
                }
              else
                {                
                  //bad message, swallow it up
                  invalidMessage = true;
                  do {
                    frame.rebuild();
                    server.receive(frame);
                  } while (frame.more);
                  writeln("invalid message received");
                }

            }
          else
            {
              send(worker, message);
            }
        }
      }
        
  }
}
