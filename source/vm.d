module vm;
const dbg = false;
import core.time;
import std.stdio;
import std.typecons;
import std.conv;
import std.json;
import threading = core.thread;
import std.concurrency;
import std.format;
import std.random;
import std.file;
import std.traits;
import std.range;

class HeapVariant
{
  Variant var;

  public this(T)(T val)
  {
    var = Variant(val); 
  }

  alias var this;

  override string toString()
  {
    return var.toString;
  }
}

enum MessageType
  {
    Connect = 0x1,
    Heartbeat = 0x2,
    Data  = 0x3,    
  }


void wdb(T...)(T msg)
{
  if(dbg)
    {
      writeln(msg);
    }
}

struct ClientMessage
{
  string client;
  MessageType type;
  string json;  
}

class Request
{
  string title;
  Tuple!(HeapVariant,string)[] actions;  
}

class GameObject
{
  int id;
  string visibility;
  HeapVariant[string] props;
  string locationKey;
  override string toString()
  {
    return "GameObject " ~ to!string(id);
  }
}

class LocationReference
{
  string key;
  HeapVariant[string] props;
  override string toString()
  {
    return format("LocRef %s", key);
  }
}

class Location
{
  LocationReference[] siblings;
  LocationReference   parent;
  LocationReference[] children; 
  string key;
  HeapVariant[string] props;
  GameObject[int] objects;
  override string toString()
  {
    return key;
  }
}

class Card : GameObject
{
  GameObject front;
  GameObject back;
}

class Stack : GameObject
{
  enum StackLocation
    {
      top,
      bottom
    }
  
  GameObject[] objects;

  void shuffle(StackLocation loc)
  {

  }
  
  void deal(int num, StackLocation sourceLoc, Stack* dest)
  {

  }

  void merge(int num, StackLocation sourceLoc, StackLocation destLoc, Stack* dest)
  {

  }

  void split(int num, Stack* dest)
  {

  }
}

class GameUniverse
{
  GameObject[int] objects;
  Location[string] locations;
  int maxId;
}

Location unpackLocation(VM* vm, HeapVariant source)
{
  if(source.peek!string)
    {
      auto key = source.get!string;
      wdb("key ", key);
      return vm.universe.locations[key];
    }
  else if (source.peek!Location)
    {
      return source.get!Location;
    }
  else if(source.peek!LocationReference)
    {
      auto lref = source.get!LocationReference;
      return vm.universe.locations[lref.key];
    }
  else
    {
      assert(false,"location source must be a string or a LocationReference");
    }
}

Tuple!(Location,Location) unpackLocations(VM* vm, HeapVariant relation, HeapVariant host)
{
  return tuple(unpackLocation(vm,relation), unpackLocation(vm,host));
}

class VM
{
  enum opcode
    {
      pop,   // throw away top item 
      ldval,
      ldvals,
      //      ldvalf,
      ldvalb,
      ldvar,
      stvar,
      p_stvar,
      ldprop, // accept game obect or location ref
      stprop,
      p_stprop,
      hasprop,
      p_hasprop,
      add,
      sub,
      mul,
      div,
      mod,
      rndi,

      concat,
      cstr,
      cint,
      
      ceq,
      cne,
      cgt,
      clt,
      beq,
      bne,
      bgt,
      blt, // ho ho ho
      branch,

      // AA and list ops
      createobj,
      cloneobj,
      getobj,
      delprop,
      p_delprop,
      delobj,
      moveobj, // change parents
      p_moveobj,
      createlist,
      appendlist,
      p_appendlist,
      removelist,
      p_removelist,
      len,
      p_len,
      index,
      p_index,
      keys,
      values,
      
      getloc,  // accepts location ref or string -> Locationref
      genloc,
      genlocref,
      setlocsibling,  // rel :: host :: locref
      p_setlocsibling, 
      setlocchild,
      p_setlocchild,
      setlocparent,
      p_setlocparent,
      // these gets return LocationReferences
      getlocsiblings,
      p_getlocsiblings,
      getlocchildren,
      p_getlocchildren,
      getlocparent,
      p_getlocparent,

      //todo: probably need ability to remove locations and links ...      
      setvis,
      p_setvis,
      adduni,
      deluni,
                       
      roll,
      
      deal,
      shuffle,
      merge,
      sort, // prop name

      // flowroutine / messaging
      genreq,
      addaction,
      p_addaction,

      suspend,
      suspendu,
      fallback,

      say,

      call,
      ret,

      dbg,  // prints to the console
      dbgl
    }

  

  // can have many machine status to enable
  // a machine rewind (un-doable co-routines)
  MachineStatus[int] machines;
  HeapVariant[int][string]  awaitingResposnes;
  int maxResponse;
  ubyte[] program;
  int requiredPlayers;

  //  string[] playerLookup;
  MonoTime[string] hearts;
  MonoTime lastHeart;
  Tid zmqThread;
  GameUniverse universe;
  string[int] strings;  //string table
  bool finished;

  @property HeapVariant[string] players()
  {
     auto p = universe.objects[-1].props["players"].peek!(HeapVariant[string]);
     return (*p);
  }
  
  bool ContainsPlayer(string clientId)
  {
    auto p = universe.objects[-1].props["players"].peek!(HeapVariant[string]);
    if(clientId in *p)
      {
        return true;
      }
    return false;

  }
  
  void AddPlayer(string clientId)
  {
    auto p = universe.objects[-1].props["players"].peek!(HeapVariant[string]);
    GameObject player = new GameObject();
    player.props["clientid"]= new HeapVariant(clientId);
    player.id = universe.maxId++;
    (*p)[clientId] = new HeapVariant(player);
    wdb("DSDSA", *p);
  }
}


struct StackFrame
{
  HeapVariant[string] locals;
  int returnAddress;
}

struct MachineStatus
{
  int pc;
  StackFrame[] callStack;
  HeapVariant[] evalStack;
  @property StackFrame* currentFrame(){ return &callStack[$-1]; }
}

void push(MachineStatus* cr, HeapVariant value)
{
  cr.evalStack~=value;
}

auto pop(MachineStatus* cr)
{
  auto val = cr.evalStack[$-1];
  cr.evalStack = cr.evalStack[0..$-1];
  return val;
}

auto peek(MachineStatus* ms)
{
  return ms.evalStack[$-1];
}

auto pop2(MachineStatus* cr)
{
  auto val = tuple(cr.evalStack[$-1],cr.evalStack[$-2]);
  cr.evalStack = cr.evalStack[0..$-2];
  return val;
}

ubyte readByte(MachineStatus* cr, const VM* vm)
{
  auto res = vm.program[cr.pc];
  cr.pc++;
  return res;
}

short readWord(MachineStatus* cr, const VM* vm)
{
  ushort res = readByte(cr,vm) << 8;
  res |= readByte(cr,vm);
  return res;
}

int readInt(MachineStatus* cr, const VM* vm)
{
  int res = readWord(cr, vm) << 16;
  res |= readWord(cr,vm);
  return res;
}

string toRequestJson(VM* vm, string header, Tuple!(HeapVariant,string)[] pairs )
{
  JSONValue js;
  js["type"] = "request";  
  js["header"] = header;
  JSONValue[] choices;

  foreach(kvp;pairs)
    {
      JSONValue choice;
      if(kvp[0].peek!int)
        {
          choice["id"] = kvp[0].get!int;
        }
      else if(kvp[0].peek!string)
        {
          choice["id"] = kvp[0].get!string;
        }
      else
        {
          assert(false, "currently only support ints and strings in json requests");
        }
      choice["text"] = kvp[1];
      choices ~= choice;
    }
    js["choices"] = JSONValue(choices);
  return js.toString;
}

string getString(MachineStatus* ms, VM* vm)
{
  auto lookup = readInt(ms,vm);
  return vm.strings[lookup];
}

GameObject[] getGameObjects(T)(T input)
{
  GameObject[] output;
  static if(is(T == GameObject))
    {
      output ~= input;
      output ~= getGameObjects(input.props);
    }
  else static if(is(T == HeapVariant[]) || is(T == HeapVariant[string]))
    {
      foreach(v;input)
        {
          if(v.peek!GameObject)
            {
               output ~= getGameObjects(v.get!GameObject);
            }
          else if(v.peek!(HeapVariant[]))
            {
              output ~= getGameObjects(v.get!(HeapVariant[]));
            }
          else if(v.peek!(HeapVariant[string]))
            {
              output ~= getGameObjects(v.get!(HeapVariant[string]));
            }
        }
    }
        
  return output;
}

void moveObjectRec(VM* vm, Location targetLoc, GameObject obj)
{
  //moving to an object always causes an object to exist in the universe
  if(obj.id !in vm.universe.objects)
    {
      wdb("adding ", obj.id, " to universe");
      vm.universe.objects[obj.id] = obj;
    }
          
  //remove from current location
  if(obj.locationKey != null && obj.locationKey != "")
    {
      auto currentLocation = vm.universe.locations[obj.locationKey];
      currentLocation.objects.remove(obj.id);              
    }

  obj.locationKey = targetLoc.key;
  targetLoc.objects[obj.id] = obj;

  // we must move all objects contained within this as well
  auto toProcess = getGameObjects(obj.props);

  foreach(go;toProcess)
    {
      if(go.locationKey != null && go.locationKey != "")
        {
          auto currentLocation = vm.universe.locations[obj.locationKey];
          currentLocation.objects.remove(obj.id);              
        }
      go.locationKey = targetLoc.key;
      targetLoc.objects[go.id] = obj;
    }
}

void stprop(string name, HeapVariant obj, HeapVariant val)
{
  if(obj.peek!GameObject)
    {
      (obj.get!GameObject()).props[name] = val;
    }
  else if (obj.peek!Location)
    {
      auto lref = obj.get!Location;
       if(is(val == HeapVariant))
        {
          lref.props[name] = val;
        }
      else
        {
          lref.props[name] = new HeapVariant(val);
        }              
    }
  else if (obj.peek!LocationReference)
    {
      auto lref = obj.get!LocationReference;
      if(is(val == HeapVariant))
        {
          lref.props[name] = val;
        }
      else
        {
          lref.props[name] = new HeapVariant(val);
        }
    }
  else
    {
      assert(false, "stprop only supports GameObject and LocationReference");
    }
}

bool step(MachineStatus* ms, VM* vm)
{
  // try
  //   {
      
      auto ins = cast(vm.opcode)readByte(ms,vm);
      wdb("ins : ", ins);
      switch(ins)
        {
        case vm.opcode.pop:
          pop(ms);
          break;
          
        case vm.opcode.ldval:
          auto val = readInt(ms,vm);
          wdb("ldval ", val);
          push(ms,new HeapVariant(val));
          break;

        case vm.opcode.ldvals:
          auto s = getString(ms,vm);
          wdb("ldvals ", s);
          push(ms,new HeapVariant(s));
          wdb("stack  ", ms.evalStack);
          break;

        case vm.opcode.ldvalb:
          int b = readInt(ms,vm);
          wdb("ldvalb ", b!=0);
          push(ms,new HeapVariant(b!=0));
          break;
      
        case vm.opcode.ldvar: // str
          // next int will be a index in the string table
          // which is then looked up in the current stack
          // frame locals or the global (bottom) frame
          auto index = getString(ms,vm);

          if(index in ms.currentFrame.locals)
            {
              wdb("ldvar local ", index, " : ", ms.currentFrame.locals[index].var);
              push(ms,ms.currentFrame.locals[index]);
            }
          else if(ms.callStack.length > 1 && index in ms.callStack[0].locals)
            {
              wdb("ldvar global ", index, " : ", ms.callStack[0].locals[index].var);
              push(ms,ms.callStack[0].locals[index]);
            }
          else
            {
              assert(0, format("variable %s was not found in current or global vars", index));
            }

          break;

        case vm.opcode.stvar: // str
          auto index = getString(ms,vm);
          auto val = pop(ms);
          wdb("stvar ", index, " = ", val.var);
          ms.currentFrame.locals[index]=val;
          break;

        case vm.opcode.p_stvar: // str
          auto index = getString(ms,vm);
          auto val = peek(ms);
          wdb("stvar ", index, " = ", val.var);
          ms.currentFrame.locals[index]=val;
          break;

        case vm.opcode.ldprop: // propname, obj
          auto name = pop(ms);
          assert(name.peek!string);
          auto obj = pop(ms);
          HeapVariant result;
          if(obj.peek!GameObject)
            {
              auto prop = (obj.get!GameObject()).props[name.get!string()];
              if(is(prop == HeapVariant))
                {
                  result = prop;
                }
              else
                {
                  result = new HeapVariant(prop);
                }              
            }
          else if(obj.peek!LocationReference)
            {
              auto loc = obj.peek!LocationReference;
              auto prop = loc.props[name.get!string()];
              if(is(prop == HeapVariant))
                {
                  result = prop;
                }
              else
                {
                  result = new HeapVariant(prop);
                }  
            }
          else
            {
              assert(false, "ldprop only accepts GameObject and LocationReference");
            }


          wdb("ldprop ", name.var , " : ", result.var);
          push(ms,result);      
          break;

        case vm.opcode.hasprop:
          auto name = pop(ms);
          assert(name.peek!string);
          auto key = name.get!string;
          auto obj = pop(ms);
          if(obj.peek!GameObject)
            {
              push(ms, new HeapVariant((key in (obj.get!GameObject()).props) != null));
            }
          //else if (obj.peek!Location)
            // {
            //   auto lref = obj.get!Location;
            //   auto key = name.get!string;
            //   if(is(val == HeapVariant))
            //     {
            //       lref.props[key] = val;
            //     }
            //   else
            //     {
            //       lref.props[key] = new HeapVariant(val);
            //     }

              
            // }
          else if (obj.peek!LocationReference)
            {
              auto lref = obj.get!LocationReference;
              push(ms,new HeapVariant((key in lref.props) != null));

            }
          else
            {
              assert(false, "stprop only supports GameObject and LocationReference");
            }
          break;
        case vm.opcode.stprop: // val :: key :: obj
          auto val = pop(ms);
          auto name = pop(ms);
          auto obj = pop(ms);
          stprop(name.get!string,obj,val);
          break;

        case vm.opcode.p_stprop: // val :: key :: obj
          auto val = pop(ms);
          auto name = pop(ms);
          auto obj = peek(ms);
          stprop(name.get!string,obj,val);
          //todo: announce
          break;
           
        case vm.opcode.add: 
          auto res = pop2(ms);
          wdb("add ", res);
          if(res[0].peek!string && res[1].peek!string)
            {
              // for the moment allow simple "adding" of strings
              push(ms, new HeapVariant(res[1] ~ res[0]));
            }
          
          else if(res[0].peek!int && res[1].peek!string)
            {
              push(ms, new HeapVariant(res[1] ~ to!string(res[0].get!int)));
            }
          else
            {
              push(ms,new HeapVariant(res[1] + res[0]));
            }
          break;

        case vm.opcode.sub: 
          auto res = pop2(ms);
          wdb("sub ", res[0]," ", res[1]);
          push(ms,new HeapVariant(res[0] - res[1]));
          break;

        case vm.opcode.mul: 
          auto res = pop2(ms);
          wdb("mul ", res);
          push(ms,new HeapVariant(res[0] * res[1]));      
          break;

        case vm.opcode.div:
          auto res = pop2(ms);
          wdb("quot ", res);
          push(ms,new HeapVariant(res[0] + res[1]));      
          break;

        case vm.opcode.mod:
          auto res = pop2(ms);
          wdb("mod ", res);
          push(ms,new HeapVariant(res[0] % res[1]));      
          break;

        case vm.opcode.rndi: // min max
          auto vals = pop2(ms);
          assert(vals[0].peek!int);
          assert(vals[1].peek!int);
          wdb("rndi ", vals);
          push(ms, new HeapVariant(uniform(vals[0].get!int,vals[1].get!int)));
          break;          
          
        case vm.opcode.ceq:
          auto vals = pop2(ms);
          wdb("ceq ", vals[0].var, " == ", vals[1].var              );
          push(ms, new HeapVariant(vals[0].var == vals[1].var));
          break;

        case vm.opcode.cne:
          auto vals = pop2(ms);
          wdb("cne ", vals);
          push(ms, new HeapVariant(vals[0].var != vals[1].var));
          break;

        case vm.opcode.clt:
          auto vals = pop2(ms);
          wdb("clt ", vals);
          wdb("clt ", vals[0].var, " == ", vals[1].var              );
          push(ms, new HeapVariant(vals[0].var < vals[1].var));
          break;

        case vm.opcode.cgt:
          auto vals = pop2(ms);
          wdb("cgt ", vals);
          push(ms, new HeapVariant(vals[0].var > vals[1].var));
          break;

        case vm.opcode.beq: // address vals
          auto address = readInt(ms,vm);
          auto vals = pop2(ms);
          wdb("beq ", vals, " : ", address);
          if(vals[0].var == vals[1].var)
            {
              ms.pc += address - 5;
            }
          break;

        case vm.opcode.bne: // address vals
          auto address = readInt(ms,vm);
          auto vals = pop2(ms);
          wdb("bne ", vals[0].var, " ", vals[1].var, " : ", address);
          if(vals[0].var != vals[1].var)
            {
              wdb("pc was ", ms.pc);
              // - 5 because 4 are the address itself
              // and 1 to comensate for the ++ at the step start
              ms.pc += (address - 5);
              wdb("now ", ms.pc);
            }
          break;

        case vm.opcode.bgt: // address vals
          auto address =readInt(ms, vm);
          auto vals = pop2(ms);
          wdb("bgt ", vals, " : ", address);
          if(vals[0].var > vals[1].var)
            {
              ms.pc += address - 5;
            }
          break;

        case vm.opcode.blt: // address vals
          //BACON LETTUCE TOMATO
          auto address = readInt(ms,vm);
          auto vals = pop2(ms);
          wdb("blt ", vals, " : ", address);
          if(vals[0].var < vals[1].var)
            {
              ms.pc += address - 5;
            }
          break;

        case vm.opcode.branch: // address
          auto address = readInt(ms,vm);
          ms.pc += address - 5;

          break;

        case vm.opcode.createobj:
          auto go = new GameObject();
          go.id = vm.universe.maxId++;
          push(ms, new HeapVariant(go));
          break;

        case vm.opcode.moveobj:
          wdb("stack : ", ms.evalStack);
          auto loc = unpackLocation(vm,pop(ms));
          auto obj = pop(ms).get!GameObject;

          moveObjectRec(vm, loc, obj);

          //TODO: ANnounce
          break;

                    
        case vm.opcode.cloneobj: // id. does not clone location. assigns new id. leaves on stack.
          auto ido = pop(ms);
          assert(ido.peek!int);
          auto id = ido.get!int;
          assert(id in vm.universe.objects);
          assert(!is(vm.universe.objects[id] == Location));
          auto obj = vm.universe.objects[id];
          auto newObj = new GameObject();
          newObj.visibility = obj.visibility;
          newObj.id = vm.universe.maxId++;
          foreach(kvp;obj.props.byKeyValue())
            {
              // todo: check for and clone lists
              // since they will be pointers
              obj.props[kvp.key]=kvp.value;
            }
          wdb("cloneobj ", id, " -> ", newObj.id);
          //vm.universe.objects[newObj.id] = newObj;      
          push(ms,new HeapVariant(newObj));
          //todo: announce
          break;

        case vm.opcode.getobj: // id -> obj on stack
          auto id = pop(ms);
          assert(id.peek!int);
          wdb("getobj ", id);
          push(ms, new HeapVariant(vm.universe.objects[id.get!int]));
          break;

        case vm.opcode.getloc: // name -> location on stack
          auto loc = pop(ms);
          wdb("getloc ", loc);
          string key;
          if(loc.peek!string)
            {
              key = loc.get!string;
            }
          else if(loc.peek!LocationReference)
            {
              auto locref = loc.get!LocationReference;
              key = locref.key;
            }
          else if(loc.peek!GameObject)
            {
              auto go = loc.get!GameObject;
              if(go.locationKey != null && go.locationKey != "")
                {
                  key = go.locationKey;
                }
              else
                {
                  assert(false, "no location key on object");
                }
            }
          else
            {
              assert(false, "could not determine location");
            }
          
          push(ms, new HeapVariant(vm.universe.locations[key]));
          break;
            
        case vm.opcode.delprop: // key obj
          auto key = pop(ms);
          assert(key.peek!string);
          auto objv = pop(ms);
          assert(objv.peek!GameObject);
          auto obj = objv.get!GameObject;
          wdb("delprop ", key.get!string, " : ", obj.id);
          obj.props.remove(key.get!string);
          //todo: announce
          break;

        case vm.opcode.p_delprop: // key obj
          auto key = pop(ms);
          assert(key.peek!string);
          auto objv = peek(ms);
          assert(objv.peek!GameObject);
          auto obj = objv.get!GameObject;
          wdb("delprop ", key.get!string, " : ", obj.id);
          obj.props.remove(key.get!string);
          //todo: announce
          break;

        case vm.opcode.setvis: // str obj
          auto str = pop(ms);
          assert(str.peek!string);
          auto objv = pop(ms);
          assert(objv.peek!GameObject);
          auto obj = objv.get!GameObject;
          wdb("setvis ", str.get!string, " : ", obj.id);
          obj.visibility=str.get!string;
          //todo: announce
          break;

        case vm.opcode.p_setvis: // str obj
          auto str = pop(ms);
          assert(str.peek!string);
          auto objv = peek(ms);
          assert(objv.peek!GameObject);
          auto obj = objv.get!GameObject;
          wdb("p_setvis ", str.get!string, " : ", obj.id);
          obj.visibility=str.get!string;
          //todo: announce
          break;

        case vm.opcode.genloc: // str
          auto name = pop(ms);
          assert(name.peek!string);
          assert(!(name.get!string in vm.universe.locations), "a location with this key already exists");
          auto loc = new Location();
          loc.key = name.get!string;
          vm.universe.locations[name.get!string] = loc;
          push(ms,new HeapVariant(loc));
          wdb("universe location count now ", vm.universe.locations.length);
          //todo: announce
          break;

        case vm.opcode.genlocref:
          push(ms, new HeapVariant(new LocationReference));
          break;
          
        case vm.opcode.setlocsibling:
          // (locref :: relation :: host)  both can either be a Location or a key
          auto r = pop(ms).get!LocationReference;
          auto refs = pop2(ms);
          auto locPair = unpackLocations(vm, refs[0], refs[1]); 
          r.key = locPair[0].key;
          locPair[1].siblings ~= r;
          //          writeln(locPair[1].key, " sibs now", locPair[1].siblings);

          
          break;

        case vm.opcode.p_setlocsibling:
          // (locref :: relation :: host)  both can either be a Location or a key
          auto r = pop(ms).get!LocationReference;
          auto rel = unpackLocation(vm, pop(ms));
          auto host = unpackLocation(vm, peek(ms));
          r.key = rel.key;
          host.siblings ~= r;          
          break;

        case vm.opcode.setlocparent:
          // (childlocref :: parent :: child)  both can either be a Location or a key                    
          auto r = pop(ms).get!LocationReference;
          auto refs = pop2(ms);
          auto locPair = unpackLocations(vm, refs[0], refs[1]);

          // link parent to child
          r.key = locPair[0].key;
          locPair[0].children ~= r;          
          // link parent to child
          auto r2 = new LocationReference();
          r2.key = locPair[0].key;
          locPair[1].parent = r2;          
          break;

        case vm.opcode.p_setlocparent:
          // (childlocref :: parent :: child)  both can either be a Location or a key
          auto r = pop(ms).get!LocationReference;
          auto parent = unpackLocation(vm, pop(ms));
          auto child = unpackLocation(vm, peek(ms));

          // link parent to child
          r.key = child.key;
          parent.children ~= r;          
          // link child to parent
          auto r2 = new LocationReference();
          r2.key = parent.key;
          child.parent = r2;          
          break;

        case vm.opcode.setlocchild:
          // (childlocref :: child  :: parent)  both can either be a Location or a key
          auto r = pop(ms).get!LocationReference;
          auto child = unpackLocation(vm,pop(ms));
          auto parent = unpackLocation(vm,pop(ms));

          // link parent to child
          r.key = child.key;
          parent.children ~= r;          
          // link child to parent
          auto r2 = new LocationReference();
          r2.key = parent.key;
          child.parent = r2;          
          break;

        case vm.opcode.p_setlocchild:
          // (childlocref :: child  :: parent)  both can either be a Location or a key
          auto r = pop(ms).get!LocationReference;
          auto child = unpackLocation(vm,pop(ms));
          auto parent = unpackLocation(vm,peek(ms));

          // link parent to child
          r.key = child.key;
          parent.children ~= r;          
          // link child to parent
          auto r2 = new LocationReference();
          r2.key = parent.key;
          child.parent = r2;          
          break;

        case vm.opcode.getlocsiblings:
          auto loc = unpackLocation(vm, pop(ms));
          HeapVariant[] list;
          foreach(x;loc.siblings)
            {
              list ~= new HeapVariant(x);
            }
          push(ms,new HeapVariant(list));
          break;

        case vm.opcode.p_getlocsiblings:
          auto loc = unpackLocation(vm, peek(ms));
          HeapVariant[] list;
          foreach(x;loc.siblings)
            {
              list ~= new HeapVariant(x);
            }
          push(ms,new HeapVariant(list));
          break;

        case vm.opcode.getlocchildren:
          auto loc = unpackLocation(vm, pop(ms));
          HeapVariant[] list;
          foreach(x;loc.children)
            {
              list ~= new HeapVariant(x);
            }
          push(ms,new HeapVariant(list));          
          break;

        case vm.opcode.p_getlocchildren:
          auto loc = unpackLocation(vm, peek(ms));
          HeapVariant[] list;
          foreach(x;loc.children)
            {
              list ~= new HeapVariant(x);
            }
          push(ms,new HeapVariant(list));          
          break;

        case vm.opcode.getlocparent:
          auto loc = unpackLocation(vm, pop(ms));
          push(ms,new HeapVariant(loc.parent));
          break;

        case vm.opcode.p_getlocparent:
          auto loc = unpackLocation(vm, peek(ms));
          push(ms,new HeapVariant(loc.parent));

          break;

        // are these actually needed?
        // case vm.opcode.adduni: // adds object on the stack to universe
        //   auto o = pop(ms);
        //   assert(o.peek!GameObject);
        //   auto go = o.get!GameObject;
        //   vm.universe.objects[go.id] = go;
        //   break;

        // case vm.opcode.deluni: // adds object on the stack to universe
        //   auto o = pop(ms);
        //   assert(o.peek!GameObject);
        //   auto go = o.get!GameObject;
        //   vm.universe.objects.remove(go.id);
        //   break;
                   
        case vm.opcode.createlist:
          HeapVariant[] newList;
          push(ms, new HeapVariant(newList));
          break;

        case vm.opcode.appendlist: // appends top of stack to next stack (a list )
          // val :: list
          wdb("stack : ", ms.evalStack);
          auto item = pop(ms);
          wdb("item is = ", item);
          auto list = pop(ms);
          assert(list.peek!(HeapVariant[]));
          wdb("appendlist ", item, " :: ", list);          
          // we must peek here to get a pointer otherwise
          // it will get copied
          if( auto l = list.peek!(HeapVariant[]))
            {
              *l ~= item;
            }
          wdb("list now : ", (list.get!(HeapVariant[])));
          break;

        case vm.opcode.p_appendlist: // appends top of stack to next stack (a list )
          // val :: list
          wdb("stack : ", ms.evalStack);
          auto item = pop(ms);
          wdb("item is = ", item);
          auto list = peek(ms);
          assert(list.peek!(HeapVariant[]));
          wdb("appendlist ", item, " :: ", list);          
          // we must peek here to get a pointer otherwise
          // it will get copied
          if( auto l = list.peek!(HeapVariant[]))
            {
              *l ~= item;
            }
          wdb("list now : ", (list.get!(HeapVariant[])));
          break;
          
                  
        case vm.opcode.removelist: //  creates a new list removing keys
          // val :: list
          wdb("removelist");
          wdb("stack : ", ms.evalStack);
          auto key = pop(ms);
          wdb("item is = ", key.var);
          auto list = pop(ms);
          assert(list.peek!(HeapVariant[]));

          HeapVariant[] newList;
          if( auto l = list.peek!(HeapVariant[]))
            {
              foreach(i; *l)
                {
                  wdb("testing if ", i, "!= ", key.var);
                  if(i.var != key.var)
                    {
                      newList ~= i;
                    }
                }
            }

          wdb("list on stack now : ");
          foreach(l;newList)
            {
              wdb(l.var);
            }

          push(ms, new HeapVariant(newList));
          break;

        case vm.opcode.p_removelist: //  creates a new list removing keys
          // val :: list
          wdb("removelist");
          wdb("stack : ", ms.evalStack);
          auto key = pop(ms);
          wdb("item is = ", key.var);
          auto list = peek(ms);
          assert(list.peek!(HeapVariant[]));

          HeapVariant[] newList;
          if( auto l = list.peek!(HeapVariant[]))
            {
              foreach(i; *l)
                {
                  wdb("testing if ", i, "!= ", key.var);
                  if(i.var != key.var)
                    {
                      newList ~= i;
                    }
                }
            }

          wdb("list on stack now : ");
          foreach(l;newList)
            {
              wdb(l.var);
            }
          
          push(ms, new HeapVariant(newList));
          break;
          
        case vm.opcode.index:
          wdb("listindex ",ms.evalStack);
          auto index = pop(ms);
          auto list = pop(ms);
          wdb(list.var);
          assert(list.peek!(HeapVariant[]));
          auto i = index.get!int;
          if(auto listt = list.peek!(HeapVariant[]))
            {
              wdb("listindex ", (*listt), " ", index.var);
              push(ms,(*listt)[i]);

            }

          break;

        case vm.opcode.p_index:
          wdb("listindex ",ms.evalStack);
          auto index = pop(ms);
          auto list = peek(ms);
          wdb(list.var);
          assert(list.peek!(HeapVariant[]));
          auto i = index.get!int;
          if(auto listt = list.peek!(HeapVariant[]))
            {
              wdb("listindex ", (*listt), " ", index.var);
              push(ms,(*listt)[i]);

            }

          break;

        case vm.opcode.keys:
          wdb("keys");
          auto ptr = pop(ms);
          HeapVariant[string] aa;
          if(ptr.peek!(HeapVariant[string]))
            {
              aa = ptr.get!(HeapVariant[string]);
            }
          else if(ptr.peek!GameObject)
            {
              auto go = ptr.get!GameObject;
              aa = go.props;
            }
          else
            {
              assert(false, "values only supports HeapVaraint[] and GameObject");
            }
          HeapVariant[] keys;          
          foreach(k;aa.keys)
            {
              keys ~= new HeapVariant(k);
            }

          push(ms,new HeapVariant(keys));  
          break;

        case vm.opcode.values:
          wdb("values");
          auto ptr = pop(ms);
          HeapVariant[string] aa;
          if(ptr.peek!(HeapVariant[string]))
            {
              aa = ptr.get!(HeapVariant[string]);
            }
          else if(ptr.peek!GameObject)
            {
              auto go = ptr.get!GameObject;
              aa = go.props;
            }
          else
            {
              assert(false, "values only supports HeapVaraint[] and GameObject");
            }
          HeapVariant[] values;                    
          foreach(v;aa.values)
            {
              values ~= new HeapVariant(v);
            }

          push(ms,new HeapVariant(values));  
          break;
          
        case vm.opcode.len:
          auto list = pop(ms);          
          wdb("!! ", list.var);
          assert(list.peek!(HeapVariant[]));
          auto l = list.peek!(HeapVariant[]);
          auto len =(*l).length;
          push(ms,new HeapVariant(cast(int)len));
          wdb("listlen ", list);
          break;

        case vm.opcode.p_len:
          auto list = peek(ms);
          assert(list.peek!(HeapVariant[]));
          auto l = list.peek!(HeapVariant[]);
          auto len =(*l).length;
          push(ms,new HeapVariant(cast(int)len-1));
          wdb("listlen ", list);
          break;


        case vm.opcode.genreq: // string -> request on stack
          auto title = pop(ms);
          assert(title.peek!string);
          wdb("genreq ", title);
          auto r = new Request();
          r.title = title.get!string;
          push(ms, new HeapVariant(r));      
          break;

        case vm.opcode.addaction: // variant :: string :: request
          auto vals = pop2(ms);
          auto reqv = pop(ms);
          //assert(vals[0].peek!int);
          assert(vals[1].peek!string);
          assert(reqv.peek!Request);
          auto req = reqv.get!Request;
          wdb("addaction ", vals[0], vals[1], " : ", req.actions);
          req.actions ~= tuple(vals[0], vals[1].get!string);
          break;

        case vm.opcode.say: // message :: client
          wdb("val stack ", ms.evalStack[0].var, " ", ms.evalStack[1].var);
          auto msg = pop(ms);
          assert(msg.peek!string);
          auto client = pop(ms);
          assert(client.peek!string);
          auto clientid = client.get!string;
          auto cm =
            ClientMessage
            (clientid,
             MessageType.Data,
             format("{\"type\":\"chat\",\"id\":\"%s\",\"msg\":\"[server] %s\"}",
                    clientid, msg.get!string));
          writeln("sending say  message to client ", clientid, " " , cm);
          vm.zmqThread.send(cm);

          break;
      
        case vm.opcode.suspend: // clientid :: req
          auto key = pop(ms);
          assert(key.peek!string);        
          auto clientid = key.get!string;
          auto reqv = pop(ms);
          assert(reqv.peek!Request);
          auto req = reqv.get!Request;
          auto cm =
            ClientMessage
            (clientid,
             MessageType.Data,
             toRequestJson(vm, req.title, req.actions));
          writeln("sending suspend message to client ", clientid, " " , cm);
          // auto pp = vm.universe.objects[-1].props["players"].get!(Variant[string]);
          // auto players = *pp;
          //   wdb("current players ", pp, " : ", players);
          vm.zmqThread.send(cm);

          return true; //wait = Waiting.WaitRequested;

        case vm.opcode.call:
          auto address = readInt(ms,vm);
          wdb("call ", address);
          wdb("pc is currenlty ", ms.pc);
          StackFrame sf;
          sf.returnAddress = ms.pc;
          ms.callStack ~= sf;
          ms.pc += (address - 5);
          break;
          
        case vm.opcode.ret:
          wdb("ret");
          if(ms.callStack.length > 1)
            {
              ms.pc = ms.callStack[$-1].returnAddress;
              wdb("pc now ", ms.pc, " call stack length ", ms.callStack.length);
              ms.callStack = ms.callStack[0..$-1];
                            wdb("pc now ", ms.pc, " call stack length ", ms.callStack.length);
            }
          else
            {
              wdb("end of main function");
              vm.finished = true;
              return true;
            }
            
          break;
        case vm.opcode.dbg:
          write(pop(ms).var);
          break;
        case vm.opcode.dbgl:
          writeln(pop(ms).var);
          break;

        default:
          wdb("unknown opcode ", ins);
          assert(0);
        }

      return false;
      //    }
  // catch(Exception e)
  //   {
  //     wdb("Exception ! ", e);
  //     throw new Exception("");
  //     //      return false;
  //   }
}

void handleResponse(MachineStatus* ms, VM* vm, string client, JSONValue response)
{
  wdb("in handle response");
  if(response["id"].type() == JSON_TYPE.INTEGER)
    {
        wdb("in handle response int");
      push(ms, new HeapVariant(cast(int)response["id"].integer));
    }
  else if(response["id"].type() == JSON_TYPE.STRING)
    {
        wdb("in handle response str");
      push(ms, new HeapVariant(cast(string)response["id"].str));
    }
  else
    {
      wdb("in handle response fail");      
      assert(false, "unsuppored key type in json response");
    }

  

  //todo: assert reposnse is valid and expected
  // set the response of a resuming core
  
  //cr.currentFrame.locals[index] = response;
}



int readInt(ref ubyte[] input, ref int index)
{
  int x = input[index];
  x <<= 8;
  x |= input[index+1];
  x <<= 8;
  x |= input[index+2];
  x <<= 8;
  x |= input[index+3];
  index += 4;
  return x;
}

void readProgram(ref string[int] strings, ref ubyte[] prog, ref int entryPoint, ref ubyte[] input)
{
  //string table will start with an int indicating amount of strings
  //then each string prefixed with an int of how many chars
  int index = 0;
  int len = readInt(input, index);
  //  writeln(len);
  //  writeln(index);
  for(int i = 0; i < len; i++)
    {
      //      writeln("reading stirng ", i);
      int stringLen = readInt(input, index);
      //      writeln("stringlen ", stringLen);
      string s;
      for(int l = 0; l < stringLen; l++)
        {
          s ~= cast(char)input[index++];
        }
      //  writeln(s);
      strings[i] ~= s;
      // writeln(strings);
    }
  //  writeln("index at ", index);
  //  index--;
  entryPoint = readInt(input,index);
  //  writeln("entry point ", entryPoint);
  prog = input[index .. $];
}
                 

version(unittest)
{
unittest  {
  // auto prog = cast(ubyte[])read("c:\\temp\\test.scur");
  // writeln("loaded");
  // string[int] s;
  // ubyte[] outprog;
  // int entry = 0;
  // readProgram(s,outprog,entry,prog);

  // writeln(s);

  }
  
  void setupTest(VM* vm)
  {
  string[int] s;
  ubyte[] outprog;
    auto raw = cast(ubyte[])read("c:\\temp\\test.scur");

  int entry = 0;
  readProgram(s,outprog,entry, raw );
  
  //read bytecode fie
  vm.machines[0] = MachineStatus();
  wdb("entry point : ", entry);
  vm.machines[0].pc = entry;
  vm.program = outprog;
  vm.machines[0].callStack ~= StackFrame();
  vm.strings = s;
  
  vm.lastHeart = MonoTime.currTime;
  vm.zmqThread = thisTid;
  vm.requiredPlayers = 2;
  HeapVariant[string] players;
  GameObject state = new GameObject();
  state.id = -1;
  state.visibility = "";

  state.props["players"] = new HeapVariant(players);
  vm.universe = new GameUniverse();
  vm.universe.objects[-1] = state;

  vm.AddPlayer("A");
  vm.AddPlayer("B");


  // wdb("state : ", vm.universe.objects[-1].props);
  // wdb("state : ", *vm.universe.objects[-1].props["players"].get!(Variant[string]*));
  }
}

unittest {
  VM vm = new VM();
  setupTest(&vm);
  while(vm.machines[0].pc < vm.program.length && !vm.finished )
    {
      if(step(&vm.machines[0],&vm))
        {
          if(!vm.finished)
            {
              JSONValue j;
              j["id"]="Diver";
              handleResponse(&vm.machines[0], &vm, "A", j);
            }
        }
    }
  writeln("suspended or finished");
  writeln("Locations count ", vm.universe.locations.length);
  // foreach(l;vm.universe.locations)
  //   {
  //     writeln(l.key);
  //   }
    
  
}


// unittest {
//   import std.traits;
//   import std.algorithm;
//   auto ops = EnumMembers!(VM.opcode);
//   // [(list 'stvar x)    (flatten (list #x04 (get-int-bytes(check-string x))))]
//   //  [(list 'sub)        #x08]

//   auto special = ["stvar", "p_stvar",  "ldval", "ldvals", "ldvalb", "bne", "bgt", "blt", "beq", "branch", "ldvar", "call"];

//   foreach(i,o;ops)
//     {
//       string op = o.to!string;
//       if( special.any!(x=>x==op))
//         {
//           writeln("[(list '",op," x)    (flatten (list ",i," (get-int-bytes(check-string x))))]");
//         }
//       else
//         {
//           writeln("[(list '",op,") ",i,"]"); 
//         }
      
      
//     }
// }

