module vm;
const dbg = false;
import core.time;
import std.datetime;
import std.stdio;
import std.typecons;
import std.conv;
import std.json;
import std.string;
import threading = core.thread;
import std.concurrency;
import std.format;
import std.random;
import std.file;
import std.traits;
import std.range;
import std.algorithm;
import std.array;

public void delegate (string) debugOutput;



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
    if(auto f = var.peek!Function)
      {
        return format("F:%X", f.functionAddress);
      }
    else if(auto r = var.peek!Request)
      {
        return format("R : %s %s", r.title, r.actions.map!(x=>format("(%s, %s)", x[0], x[1])).join(","));
      }
    else if(auto r = var.peek!(HeapVariant[]*))
      {
        return (**r).to!string;
      }
    else
      {
        return var.toString;
      }
  }

  int opCmp(ref const HeapVariant b)
  {
    if(var.peek!int)
      {
        return var.get!int > b.get!int ? 1 : -1;
      }
    else if(var.peek!string)
      {
        return var.get!string > b.get!string ? 1 : -1;
      }
    else
      {
        assert(false, "can only sort ints");
      }
  }
}
enum MessageType
  {
    Connect = 0x1,
    Heartbeat = 0x2,
    Data  = 0x3,
    Status = 0x4,
    Universe = 0x5
  }

void wdb(T...)(T msg)
{
  if(dbg)
    {
      writeln(msg);
    }
  if(dbg && debugOutput !is null)
    {
      string s;
      foreach(m;msg)
        {
          s ~= format("%s",m);
        }
      debugOutput(s ~ "\n");
    }

      
}

void output(T...)(T msg)
{
  if(debugOutput !is null)
    {
      string s;
      foreach(m;msg)
        {
          s ~= format("%s",m);
        }
      debugOutput(s);
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
  Tuple!(string,string)[] actions;  
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
  int id;
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
  LocationReference[int] locationReferences;  
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
      brk,   // software breakpoint 
      pop,   // throw away top item 
      ldval,
      ldvals,
      //      ldvalf,
      ldvalb,
      ldvar,
      stvar,
      p_stvar,
      ldprop, // accept game obect or location ref
      p_ldprop,
      stprop,
      p_stprop,
      inc,
      dec,
      add,
      sub,
      mul,
      div,
      mod,
      rndi,

      startswith,
      p_startswith,
      endswith,
      p_endswith,
      contains,
      p_contains,
      indexof,
      p_indexof,
      substring,
      p_substring,
      
      ceq,
      cne,
      cgt,
      cgte,
      clt,
      clte,
      beq,
      bne,
      bgt,
      blt, // ho ho ho
      branch,

      // AA and list ops
      createobj,
      cloneobj,
      getobj,
      getobjs,
      delprop,
      p_delprop,
      delobj,
      moveobj, // change parents
      p_moveobj,
      createlist,
      appendlist,
      p_appendlist,
      prependlist,
      p_prependlist,
      removelist,
      p_removelist,
      len,
      p_len,
      index,
      p_index,
      keys,
      values,
      syncprop,
      
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
                       
      splitat,
      shuffle,
      sort, // number / string lists
      sortby, // prop name
      
      // flowroutine / messaging
      genreq,
      addaction,
      p_addaction,

      suspend,
      cut,
      say,

      pushscope,
      popscope,
      lambda,
      apply,
      ret,

      dbg,  // prints to the console
      dbgl
    }

  

  // can have many machine status to enable
  // a machine rewind (un-doable co-routines)
  MachineStatus[] machines;  
  int maxResponse;
  ubyte[] program;
  int requiredPlayers;
  bool isDebug = false;
  //  string[] playerLookup;
  MonoTime[string] hearts;
  MonoTime lastHeart;
  Tid zmqThread;
  GameUniverse universe;
  string[int] strings;  //string table
  bool finished;

  
  
  void Initialize(string fileName)
  {
    strings.clear;    
    auto raw = cast(ubyte[])read(fileName);
    int entry = 0;
    readProgram(strings,program,entry,raw);
    machines = [];
    universe = new GameUniverse();
    machines ~= MachineStatus();
    machines[0].pc = entry;
    machines[0].scopes ~= Scope();
    GameObject state = new GameObject();
    state.id = -1;
    state.visibility = "";
    HeapVariant[string] players;
    state.props["players"] = new HeapVariant(players);
    universe.objects[-1] = state;


  }


  
  @property MachineStatus* CurrentMachine()
  {
    return &machines[$-1];
  }
  
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

struct Scope
{
  // this could be a "stack frame" (return address)
  // a normal lexical scope (some loop)
  // a "stack frame" might have a closure scope
  HeapVariant[string] locals;
  int returnAddress;
  Scope* closureScope;
  @property bool IsFunction() { return returnAddress != 0; }
  
}

struct Function
{
  Scope* closureScope;
  int functionAddress;
}

struct MachineStatus
{
  int pc;
  Scope[] scopes;
  HeapVariant[] evalStack;
  HeapVariant waitingMessage;
  string[string] validChoices;
  @property Scope* currentFrame(){ return &scopes[$-1]; }
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

JSONValue serialize(HeapVariant var)
{

 if(var.peek!string)
   {
     return JSONValue(var.get!string);
   }
 else if(var.peek!int)
   {
     return JSONValue(var.get!int);
   }
 else if(var.peek!GameObject)
   {
     auto go = var.get!GameObject;
     return JSONValue(go.toReference);
   }
 else if(var.peek!Location)
   {
     auto loc = var.get!Location;
     return JSONValue(loc.toReference);
   }
 else if(var.peek!Function)
   {
     
   }
 else if(auto arr = var.peek!(HeapVariant[]))
   {
     JSONValue[] res;
     foreach(x;*arr)
       {
         res ~= serialize(x);              
       }
     return JSONValue(res);
     assert(false,"not supported yet");
   }
 assert(0);

}
JSONValue serialize(GameObject go)
{
  JSONValue js;  
  js["id"] = go.id;
  JSONValue props;
  foreach(p;go.props.byKeyValue)
    {
      if(p.value.peek!Function)
        {
     
        }
      else
        {
          js[p.key] = serialize(p.value); // todo :arrays
        }
    }
  return js;
}
JSONValue serialize(Location loc)
{
  JSONValue js;  
  js["key"] = loc.key;
  foreach(p;loc.props.byKeyValue)
    {
      if(p.value.peek!Function)
        {
     
        }
      else
        {
     
          js[p.key] = serialize(p.value); // todo :arrays
        }
    }
  return js;
}

string toReference(GameObject go)
{
  return format("{%s}",go.id);
}
string toReference(Location loc)
{
  return format("{%s}",loc.key);
}

void AnnounceDelta(VM* vm, string op, Tuple!(string,Variant)[] pairs, string visibility)
{
  JSONValue js;
  js["t"] = op;
  
  foreach(p;pairs)
    {
      if(p[1].peek!string)
        {
          js.object[p[0]]=p[1].get!string;
        }
      else if(p[1].peek!int)
       {
          js.object[p[0]]=p[1].get!int;
        }
      else if(p[1].peek!GameObject)
        {
          auto r = serialize(p[1].get!GameObject);
          js.object[p[0]]=r;
        }
      else if(p[1].peek!Location)
        {
          auto r = serialize(p[1].get!Location);
          js.object[p[0]]=r;
        }
      else if(auto arr = p[1].peek!(HeapVariant[]))
        {
          //todo: tidy this up
          js.object[p[0]]= serialize(new HeapVariant(p[1]));
        }
      else if(p[1].peek!Function)
        {
          //never announce funcs
        }
      else
        {
          assert(0, format("unsupported type %s", p[1]));
        }          
    }
  
  foreach(p;vm.players)
    {
      auto go = p.get!GameObject;
      //todo: only send to clients based on vis      
      auto cm =
        ClientMessage
        (go.props["clientid"].get!string,
         MessageType.Data,
         js.toString);
      if(vm.isDebug == false)
        {
          vm.zmqThread.send(cm);
        }
      else
        {
          //todo:fire delegate
        }
    }
}

string toRequestJson(VM* vm,string header, Tuple!(string,string)[] pairs, bool includeUndo )
{
  JSONValue js;
  js["t"] = "request";  
  js["header"] = header;
  JSONValue[] choices;

  foreach(kvp;pairs)
    {
      JSONValue choice;
      choice["id"] = kvp[0];      
      choice["text"] = kvp[1];
      choices ~= choice;
    }

  if(includeUndo)
    {
      JSONValue choice;
      choice["id"] = "__UNDO__";      
      choice["text"] = "";
      choices ~= choice;  
    }
  
    js["choices"] = JSONValue(choices);
  return js.toString;
}

string getString(MachineStatus* ms, VM* vm)
{
  auto lookup = readInt(ms,vm);
  //writeln(" !!! ", lookup);
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
      AnnounceDelta(vm,"aui",[tuple("o",Variant(obj))],"");
    }

  if(obj.locationKey !is null && obj.locationKey != targetLoc.key)
    {
      //remove from current location  
      auto currentLocation = vm.universe.locations[obj.locationKey];
      currentLocation.objects.remove(obj.id);                
    }

  if(obj.locationKey is null || obj.locationKey != targetLoc.key)
    {
      // move and announce
      obj.locationKey = targetLoc.key;
      targetLoc.objects[obj.id] = obj;

      AnnounceDelta(vm,"mo",[tuple("o",Variant(obj.id)),
                             tuple("l",Variant(targetLoc.key))],"");
    }

  // we must move all objects contained within this as well
  auto toProcess = getGameObjects(obj.props);

  foreach(go;toProcess)
    {
      if(go.id !in vm.universe.objects)
        {
          wdb("adding ", go.id, " to universe");
          vm.universe.objects[go.id] = go;      
          AnnounceDelta(vm,"aui",[tuple("o",Variant(go))],"");       
        }

      if(go.locationKey !is null && go.locationKey != "")
        {
          auto currentLocation = vm.universe.locations[obj.locationKey];
          currentLocation.objects.remove(obj.id);              
        }

      if(go.locationKey is null || go.locationKey != targetLoc.key)
        {
          go.locationKey = targetLoc.key;
          targetLoc.objects[go.id] = obj;
          AnnounceDelta(vm,"mo",[tuple("o",Variant(go.id)),
                                 tuple("l",Variant(targetLoc.key))],"");
        }
    }
}

void ldprop(MachineStatus* ms, string name, HeapVariant obj)
{
  HeapVariant result;
  if(obj.peek!GameObject)
    {
      GameObject go = obj.get!GameObject;
      if(name !in go.props)
        {
          assert(false, "property " ~ name ~ " does not exist");
        }      
      else if(auto arr = go.props[name].peek!(HeapVariant[]))
        {
          //pointer
          result = new HeapVariant(arr);
        }
      else
        {
          auto prop = (obj.get!GameObject()).props[name];
          if(prop.peek!HeapVariant)
            {
              result = prop;
            }
          else
            {
              result = new HeapVariant(prop);
            }
        }
    }
  else if(obj.peek!Location)
    {
      auto loc = obj.peek!Location;
      if(name !in loc.props)
        {
          assert(false, format("%s not found in %s", name, loc.key));          
        }
      auto prop = loc.props[name];
              
      if(is(prop == prop.peek!HeapVariant))
        {
          result = prop.get!HeapVariant;
        }
      else
        {
          result = new HeapVariant(prop);
        }  
    }
  else if(obj.peek!LocationReference)
    {
      auto loc = obj.peek!LocationReference;
      auto prop = loc.props[name];
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

  push(ms,result);      

}

void ensureObjectsAnnounced(VM* vm, HeapVariant val)
{
  if(auto go = val.peek!GameObject)
    {
      if(go.id !in vm.universe.objects)
        {
          //writeln("annoucenke");
          vm.universe.objects[go.id] = *go;
          AnnounceDelta(vm,"aui",[tuple("o",Variant(*go))],"");       
        }
    }
  else if(auto arr = val.peek!(HeapVariant[]))
    {
      foreach(x;*arr)
        {
          ensureObjectsAnnounced(vm, x);
        }
    }
}
void stprop(VM* vm, string name, HeapVariant obj, HeapVariant val)
{
  ensureObjectsAnnounced(vm,val);
  if(obj.peek!GameObject)
    {
      auto go = obj.get!GameObject;
      
      go.props[name] = val;
      if(val.peek!Function)
        {

        }
      else
        {
          if(go.id != -1 && go.id in vm.universe.objects)
            {
              AnnounceDelta(vm, "spg", [tuple("i",Variant(go.id)),
                                        tuple("k",Variant(name)),
                                        tuple("v",val.var)], "");
            }
        }
    }
  else if (obj.peek!Location)
    {
      auto lref = obj.get!Location;
      lref.props[name] = val;
      if(val.peek!Function)
        {

        }
      else
        {
          AnnounceDelta(vm, "spl", [tuple("i",Variant(lref.key)),
                                    tuple("k",Variant(name)),
                                    tuple("v",val.var)], "");
        }
    }
  else if (obj.peek!LocationReference)
    {
      auto lref = obj.get!LocationReference;
      lref.props[name] = val;
      if(val.peek!Function)
        {

        }
      else
        {
          AnnounceDelta(vm, "splr", [tuple("i",Variant(lref.id)),
                                     tuple("k",Variant(name)),
                                     tuple("v",val.var)], "");
        }
    }
  else
    {
      assert(false, "stprop only supports GameObject and LocationReference");
    }
}

void indexOf(MachineStatus* ms, string key, HeapVariant obj)
{
  // later we can support arrays here, for now just strings
  auto str = obj.get!string;
  import std.string : indexOf;
  push(ms, new HeapVariant(str.indexOf(key)));
}

void substring(MachineStatus* ms, int start, int len, string obj)
{
  // later we can support arrays here, for now just strings
  import std.string : indexOf;
  string split;
  if(len == -1)
    {
      split = obj[start .. $];
    }
  else
    {
      split = obj[start .. start + len];
    }
  
  push(ms, new HeapVariant(split));
}

void contains(MachineStatus* ms, string key, HeapVariant obj)
{
  if(obj.peek!GameObject)
    {
      push(ms, new HeapVariant((key in (obj.get!GameObject()).props) != null));
    }
  else if(obj.peek!string)
    { 
     auto val = obj.get!string;
      import std.string : indexOf;
      push(ms, new HeapVariant(val.indexOf(key) > -1));
    }
  else if(auto lst = obj.peek!(HeapVariant[]))
    {
      //this only works with strings presently
      foreach(i;*lst)
        {
          if(i.peek!string && i.var == key)
            {
              push(ms, new HeapVariant(true));
              break;
            }
        }

  
    }
    else if(auto lst = obj.peek!(HeapVariant[]*))
    {
      //this only works with strings presently
      foreach(i;**lst)
        {
          if(i.peek!string && i.var == key)
            {
              push(ms, new HeapVariant(true));
              break;
            }
        }  
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
      assert(false, "contains only supports GameObject and LocationReference");
    }

}

void locateVar(MachineStatus* ms, string index, Scope* currentScope)
{
  if(index in currentScope.locals)
    {
      //    wdb("ldvar local ", index, " : ", ms.currentFrame.locals[index].var);
      if(auto arr = currentScope.locals[index].peek!(HeapVariant[]))
        {
          push(ms, new HeapVariant(arr));
        }
      else
        {
          push(ms,currentScope.locals[index]);
        }

    }
  else if(currentScope.closureScope !is null)
   {
     locateVar(ms, index, currentScope.closureScope);
   }
  else
    {
      assert(false, format("could not locate var %s", index));
    }
}

VM.opcode peekOpcode(VM* vm)
{
  return cast(vm.opcode)vm.program[vm.CurrentMachine.pc];
}

bool step(VM* vm)
{
  MachineStatus* ms = vm.CurrentMachine;
  // try
  //   {
      
  auto ins = cast(vm.opcode)readByte(ms,vm);
  wdb("ins ", ms.pc," : ", ins);
  // wdb(ms.evalStack);
  switch(ins)
    {
    case vm.opcode.brk:
      // do nothing - up to the debugger to honour this
      break;
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
      //wdb("ldvalb ", b!=0);
      push(ms,new HeapVariant(b!=0));
      break;
      
    case vm.opcode.ldvar: // str
      // next int will be a index in the string table
      // which is then looked up in the current stack
      // frame locals or the global (bottom) frame
      auto index = getString(ms,vm);
      wdb("ldvar ", index);
      locateVar(ms, index, ms.currentFrame);      
      wdb("stack now ", ms.evalStack);
      break;

    case vm.opcode.stvar: // str
      auto index = getString(ms,vm);
      auto val = pop(ms);
      wdb("stvar ", index, " = ", val.var);
      ms.currentFrame.locals[index]=val;
      wdb("stack now ", ms.evalStack);
      break;

    case vm.opcode.p_stvar: // str
      auto index = getString(ms,vm);
      auto val = peek(ms);
      wdb("p_stvar ", index, " = ", val.var);
      ms.currentFrame.locals[index]=val;
      wdb("stack now ", ms.evalStack);
      break;

    case vm.opcode.ldprop: // propname, obj          
      auto name = pop(ms);
      assert(name.peek!string);
      auto obj = pop(ms);
      ldprop(ms,name.get!string,obj);
      break;

    case vm.opcode.p_ldprop: // propname, obj          
      auto name = pop(ms);
      assert(name.peek!string);
      auto obj = peek(ms);
      ldprop(ms,name.get!string,obj);
      break;

    case vm.opcode.stprop: // val :: key :: obj
      auto val = pop(ms);
      auto name = pop(ms);
      auto obj = pop(ms);
      stprop(vm, name.get!string,obj,val);

      break;

    case vm.opcode.p_stprop: // val :: key :: obj
      auto val = pop(ms);
      auto name = pop(ms);
      auto obj = peek(ms);
      stprop(vm, name.get!string,obj,val);
      break;

    case vm.opcode.inc:
      {
        auto num = peek(ms);
        if(auto n = num.peek!int)
          {
            (*n)++;
          }
        else
          {
            assert(false, "expected number");
          }
        break;
      }
    case vm.opcode.dec:
      {
        auto num = peek(ms);
        if(auto n = num.peek!int)
          {
            (*n)--;
          }
        else
          {
            assert(false, "expected number");
          }
        break;
      }

    case vm.opcode.add: 
      auto res = pop2(ms);
      //writeln("add ", res);
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
      //wdb("sub ", res[0]," ", res[1]);
      push(ms,new HeapVariant(res[0] - res[1]));
      break;

    case vm.opcode.mul: 
      auto res = pop2(ms);
      //wdb("mul ", res);
      push(ms,new HeapVariant(res[0] * res[1]));      
      break;

    case vm.opcode.div:
      auto res = pop2(ms);
      //wdb("quot ", res);
      push(ms,new HeapVariant(res[0] + res[1]));      
      break;

    case vm.opcode.mod:
      auto res = pop2(ms);
      //wdb("mod ", res);
      push(ms,new HeapVariant(res[0] % res[1]));      
      break;

    case vm.opcode.rndi: // min max
      auto vals = pop2(ms);
      assert(vals[0].peek!int);
      assert(vals[1].peek!int);
      //wdb("rndi ", vals);
      push(ms, new HeapVariant(uniform(vals[0].get!int,vals[1].get!int)));
      break;          

    case vm.opcode.startswith:
      auto val = pop(ms);
      auto str = pop(ms);
      assert(val.peek!string);
      assert(str.peek!string);
      auto v = val.get!string;
      auto s = str.get!string;
      push(ms, new HeapVariant(s.startsWith(v)));
      break;
          
    case vm.opcode.p_startswith:
      auto val = pop(ms);
      auto str = peek(ms);
      assert(val.peek!string);
      assert(str.peek!string);
      auto v = val.get!string;
      auto s = str.get!string;
      push(ms, new HeapVariant(s.startsWith(v)));
      break;
          
    case vm.opcode.endswith:
      auto val = pop(ms);
      auto str = pop(ms);
      assert(val.peek!string);
      assert(str.peek!string);
      auto v = val.get!string;
      auto s = str.get!string;
      push(ms, new HeapVariant(s.endsWith(v)));
      break;
          
    case vm.opcode.p_endswith:
      auto val = pop(ms);
      auto str = peek(ms);
      assert(val.peek!string);
      assert(str.peek!string);
      auto v = val.get!string;
      auto s = str.get!string;
      push(ms, new HeapVariant(s.endsWith(v)));
      break;

    case vm.opcode.indexof:
      auto val = pop(ms);
      auto str = pop(ms);
      assert(val.peek!string);
      assert(str.peek!string);
      auto v = val.get!string;
      auto s = str.get!string;
      indexOf(ms, v, str);
      break;

    case vm.opcode.p_indexof:
      auto val = pop(ms);
      auto str = peek(ms);
      assert(val.peek!string);
      assert(str.peek!string);
      auto v = val.get!string;
      auto s = str.get!string;
      indexOf(ms, v, str);
      break;

    case vm.opcode.substring:
      auto len = pop(ms);
      auto start = pop(ms);
      auto str = pop(ms);
      assert(str.peek!string);
      assert(len.peek!int);
      assert(start.peek!int);
      substring(ms, start.get!int, len.get!int,  str.get!string);
      break;
          
    case vm.opcode.p_substring:
      auto len = pop(ms);
      auto start = pop(ms);
      auto str = peek(ms);
      assert(str.peek!string);
      assert(len.peek!int);
      assert(start.peek!int);
      substring(ms, start.get!int, len.get!int,  str.get!string);
      break;
          
    case vm.opcode.contains:
      auto val = pop(ms);
      auto obj = pop(ms);
      assert(val.peek!string);
      auto v = val.get!string;
      contains(ms, v, obj);
      break;
          
    case vm.opcode.p_contains:      
      auto val = pop(ms);
      auto obj = peek(ms);
      assert(val.peek!string);
      auto v = val.get!string;
      contains(ms, v, obj);
      break;

    case vm.opcode.ceq:
      auto vals = pop2(ms);
      //wdb("ceq ", vals[0].var, " == ", vals[1].var              );
      push(ms, new HeapVariant(vals[0].var == vals[1].var));
      break;

    case vm.opcode.cne:
      auto vals = pop2(ms);
      //wdb("cne ", vals);
      push(ms, new HeapVariant(vals[0].var != vals[1].var));
      break;

    case vm.opcode.clt:
      auto vals = pop2(ms);
      push(ms, new HeapVariant(vals[0].var < vals[1].var));
      break;

    case vm.opcode.clte:
      auto vals = pop2(ms);
      push(ms, new HeapVariant(vals[0].var <= vals[1].var));
      break;
      
    case vm.opcode.cgt:
      auto vals = pop2(ms);
      push(ms, new HeapVariant(vals[0].var > vals[1].var));
      break;

    case vm.opcode.cgte:
      auto vals = pop2(ms);
      //wdb("cgt ", vals);
      push(ms, new HeapVariant(vals[0].var >= vals[1].var));
      break;

      
    case vm.opcode.beq: // address vals
      auto address = readInt(ms,vm);
      auto vals = pop2(ms);

      if(vals[0].var == vals[1].var)
        {
          //wdb("beq ", vals, " : ", address);
          ms.pc += address - 5;
        }
      break;

    case vm.opcode.bne: // address vals
      auto address = readInt(ms,vm);
      auto vals = pop2(ms);
      //wdb("bne ", vals[0].var, " ", vals[1].var, " : ", address);
      if(vals[0].var != vals[1].var)
        {
          //wdb("pc was ", ms.pc);
          // - 5 because 4 are the address itself
          // and 1 to comensate for the ++ at the step start
          ms.pc += (address - 5);
          //wdb("now ", ms.pc);
        }
      break;

    case vm.opcode.bgt: // address vals
      auto address =readInt(ms, vm);
      auto vals = pop2(ms);
      //wdb("bgt ", vals, " : ", address);
      if(vals[0].var > vals[1].var)
        {
          ms.pc += address - 5;
        }
      break;

    case vm.opcode.blt: // address vals
      //BACON LETTUCE TOMATO
      auto address = readInt(ms,vm);
      auto vals = pop2(ms);
      //wdb("blt ", vals, " : ", address);
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
      //wdb("stack : ", ms.evalStack);
      auto loc = unpackLocation(vm,pop(ms));
      auto obj = pop(ms).get!GameObject;
      moveObjectRec(vm, loc, obj);      
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
      //wdb("cloneobj ", id, " -> ", newObj.id);
      //vm.universe.objects[newObj.id] = newObj;      
      push(ms,new HeapVariant(newObj));
      //todo: announce
      break;

    case vm.opcode.getobj: // id -> obj on stack
      auto id = pop(ms);
      assert(id.peek!int);
      //wdb("getobj ", id);
      push(ms, new HeapVariant(vm.universe.objects[id.get!int]));
      break;

    case vm.opcode.getobjs: // loc -> obj[] on stack
      auto id = pop(ms);
      auto loc = unpackLocation(vm,id);
      HeapVariant[] items;
      foreach(i;loc.objects)
        {
          items ~= new HeapVariant(i);
        }
      push(ms, new HeapVariant(items));
      break;

    case vm.opcode.getloc: // name -> location on stack
      auto loc = pop(ms);
      //wdb("getloc ", loc);
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
      //wdb("delprop ", key.get!string, " : ", obj.id);
      obj.props.remove(key.get!string);
      if(obj.id in vm.universe.objects)
        {
          AnnounceDelta(vm, "dp",[tuple("o",Variant(obj.id)),
                                  tuple("k",Variant(key))], "");
        }
      break;

    case vm.opcode.p_delprop: // key obj
      auto key = pop(ms);
      assert(key.peek!string);
      auto objv = peek(ms);
      assert(objv.peek!GameObject);
      auto obj = objv.get!GameObject;
      //wdb("delprop ", key.get!string, " : ", obj.id);
      obj.props.remove(key.get!string);
      if(obj.id in vm.universe.objects)
        {
          AnnounceDelta(vm, "dp",[tuple("o",Variant(obj.id)),
                                  tuple("k",Variant(key))], "");
        }
      break;

    case vm.opcode.setvis: // str obj
      auto str = pop(ms);
      assert(str.peek!string);
      auto objv = pop(ms);
      assert(objv.peek!GameObject);
      auto obj = objv.get!GameObject;
      //wdb("setvis ", str.get!string, " : ", obj.id);
      obj.visibility=str.get!string;
      //todo: announce
      break;

    case vm.opcode.p_setvis: // str obj
      auto str = pop(ms);
      assert(str.peek!string);
      auto objv = peek(ms);
      assert(objv.peek!GameObject);
      auto obj = objv.get!GameObject;
      //wdb("p_setvis ", str.get!string, " : ", obj.id);
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
      //wdb("universe location count now ", vm.universe.locations.length);
      AnnounceDelta(vm, "gl",[tuple("k",Variant(loc.key))], "");
      break;

    case vm.opcode.genlocref:
      auto loc = new LocationReference();
      loc.id = vm.universe.maxId++;
      vm.universe.locationReferences[loc.id] = loc;
      push(ms, new HeapVariant(loc));
      AnnounceDelta(vm, "glr",[tuple("l",Variant(loc.id))], "");
      break;
          
    case vm.opcode.setlocsibling:
      // (locref :: relation :: host)  both can either be a Location or a key
      auto r = pop(ms).get!LocationReference;
      auto refs = pop2(ms);
      auto locPair = unpackLocations(vm, refs[0], refs[1]); 
      r.key = locPair[0].key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r.id)),
                                tuple("k",Variant(r.key))], "");

      locPair[1].siblings ~= r;
      AnnounceDelta(vm, "sls",[tuple("l",Variant(locPair[1].key)),
                               tuple("lr",Variant(r.id))], "");
      break;

    case vm.opcode.p_setlocsibling:
      // (locref :: relation :: host)  both can either be a Location or a key
      auto r = pop(ms).get!LocationReference;
      auto rel = unpackLocation(vm, pop(ms));
      auto host = unpackLocation(vm, peek(ms));
      r.key = rel.key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r.id)),
                                tuple("k",Variant(r.key))], "");

      host.siblings ~= r;
      AnnounceDelta(vm, "sls",[tuple("l",Variant(host.key)),
                               tuple("lr",Variant(r.id))], "");
      break;

    case vm.opcode.setlocparent:      // (childlocref :: parent :: child)  both can either be a Location or a key     
      auto r = pop(ms).get!LocationReference;
      auto refs = pop2(ms);
      auto locPair = unpackLocations(vm, refs[0], refs[1]);
      // link parent to child
      r.key = locPair[0].key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r.id)),
                               tuple("k",Variant(r.key))], "");
     
      locPair[0].children ~= r;
      AnnounceDelta(vm, "slp",[tuple("p",Variant(locPair[0].key)),
                               tuple("lr",Variant(r.id))], "");

      // link parent to child
      auto r2 = new LocationReference();
      r2.id = vm.universe.maxId++;
      AnnounceDelta(vm, "glr",[tuple("l",Variant(r2.id))],"");                                    
      r2.key = locPair[0].key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r2.id)),
                                tuple("k",Variant(r2.key))], "");

      locPair[1].parent = r2;
      AnnounceDelta(vm, "slc",[tuple("c",Variant(locPair[1].key)),
                               tuple("lr",Variant(r2.id))], "");
      break;

    case vm.opcode.p_setlocparent:
      // (childlocref :: parent :: child)  both can either be a Location or a key
      auto r = pop(ms).get!LocationReference;
      auto parent = unpackLocation(vm, pop(ms));
      auto child = unpackLocation(vm, peek(ms));

      // link parent to child
      r.key = child.key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r.id)),
                                tuple("k",Variant(r.key))], "");

      AnnounceDelta(vm, "slc",[tuple("c",Variant(child.key)),
                               tuple("lr",Variant(r.id))], "");
      
      parent.children ~= r;          
      // link child to parent
      auto r2 = new LocationReference();
      AnnounceDelta(vm, "glr",[tuple("l",Variant(r2.id))],"");                                    
      r2.key = parent.key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r2.id)),
                                tuple("k",Variant(r2.key))], "");

      child.parent = r2;          
      AnnounceDelta(vm, "slp",[tuple("p",Variant(parent.key)),
                               tuple("lr",Variant(r2.id))], "");

      break;

    case vm.opcode.setlocchild:
      // (childlocref :: child  :: parent)  both can either be a Location or a key
      auto r = pop(ms).get!LocationReference;
      auto child = unpackLocation(vm,pop(ms));
      auto parent = unpackLocation(vm,pop(ms));

      // link parent to child
      r.key = child.key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r.id)),
                                tuple("k",Variant(r.key))], "");

      parent.children ~= r;
      AnnounceDelta(vm, "slp",[tuple("p",Variant(parent.key)),
                               tuple("lr",Variant(r.id))], "");

      // link child to parent
      auto r2 = new LocationReference();
      r2.key = parent.key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r2.id)),
                                tuple("k",Variant(r2.key))], "");

      child.parent = r2;
      AnnounceDelta(vm, "slc",[tuple("c",Variant(child.key)),
                               tuple("lr",Variant(r2.id))], "");

      break;

    case vm.opcode.p_setlocchild:
      // (childlocref :: child  :: parent)  both can either be a Location or a key
      auto r = pop(ms).get!LocationReference;
      auto child = unpackLocation(vm,pop(ms));
      auto parent = unpackLocation(vm,peek(ms));

      // link parent to child
      r.key = child.key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r.id)),
                                tuple("k",Variant(r.key))], "");

      parent.children ~= r;
      AnnounceDelta(vm, "slp",[tuple("p",Variant(parent.key)),
                               tuple("lr",Variant(r.id))], "");

      // link child to parent
      auto r2 = new LocationReference();
      r2.key = parent.key;
      AnnounceDelta(vm, "slrk",[tuple("i",Variant(r2.id)),
                                tuple("k",Variant(r2.key))], "");

      child.parent = r2;
      AnnounceDelta(vm, "slc",[tuple("c",Variant(child.key)),
                               tuple("lr",Variant(r2.id))], "");

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
 
    case vm.opcode.adduni: // adds object on the stack to universe
      auto o = pop(ms);
      assert(o.peek!GameObject);
      auto go = o.get!GameObject;
      vm.universe.objects[go.id] = go;
      //todo:announce
      break;

    case vm.opcode.deluni:
      auto o = pop(ms);
      assert(o.peek!GameObject);
      auto go = o.get!GameObject;
      vm.universe.objects.remove(go.id);
      AnnounceDelta(vm, "dui",[tuple("u",Variant(go.id))], "");
      break;
                   
    case vm.opcode.createlist:
      HeapVariant[] newList;
      push(ms, new HeapVariant(newList));
      break;

    case vm.opcode.appendlist: // appends top of stack to next stack (a list )
      auto item = pop(ms);
      auto list = pop(ms);
      if( auto l = list.peek!(HeapVariant[]*))
        {
          **l ~= item;
        }
      else if(auto l = list.peek!(HeapVariant[]))
        {
          // this case happens with a new list
          *l ~= item;
        }
      else
        {
          assert(false, "invalid array");
        }
      break;

    case vm.opcode.p_appendlist: // appends top of stack to next stack (a list )
      // val :: list
      //wdb("stack : ", ms.evalStack);
      auto item = pop(ms);
      //wdb("item is = ", item);
      auto list = peek(ms);
      //wdb("appendlist ", item, " :: ", list);          
      // we must peek here to get a pointer otherwise
      // it will get copied
      if( auto l = list.peek!(HeapVariant[]*))
        {          
          **l ~= item;
        }
      else if(auto l = list.peek!(HeapVariant[]))
        {
          // this case happens with a new list not bound ...
          *l ~= item;
        }
      else
        {
          assert(false, "invalid array");
        }
      //wdb("list now : ", (list.get!(HeapVariant[])));
      break;
          
    case vm.opcode.prependlist: // appends top of stack to next stack (a list )
      auto item = pop(ms);
      auto list = pop(ms);
      if( auto l = list.peek!(HeapVariant[]*))
        {
          **l = [item] ~ **l;
        }
      else if(auto l = list.peek!(HeapVariant[]))
        {
          // this case happens with a new list
          *l = [item] ~ *l;
        }
      else
        {
          assert(false, "invalid array");
        }
      break;
                  
    case vm.opcode.removelist: //  removes matching elements in place
      // val :: list
      auto key = pop(ms);
      auto list = pop(ms);
      assert(list.peek!(HeapVariant[]*));

      HeapVariant[] newList;
      if( auto l = list.peek!(HeapVariant[]*))
        {          
          foreach(i; **l)
            {
              if(i.var != key.var)
                {
                  newList ~= i;
                }
            }
          **l = newList;
        }

      break;


    case vm.opcode.p_removelist:
      auto key = pop(ms);
      auto list = peek(ms);
      assert(list.peek!(HeapVariant[]*));

      HeapVariant[] newList;
      if( auto l = list.peek!(HeapVariant[]*))
        {          
          foreach(i; **l)
            {
              if(i.var != key.var)
                {
                  newList ~= i;
                }
            }
          **l = newList;
        }
      break;
          
    case vm.opcode.index:
      //wdb("listindex ",ms.evalStack);
      auto index = pop(ms);
      auto list = pop(ms);
      //wdb(list.var);
      auto i = index.get!int;
      if(auto listt = list.peek!(HeapVariant[]))
        {
          //wdb("listindex ", (*listt), " ", index.var);
          push(ms,(*listt)[i]);
        }
      else if(auto listt = list.peek!(HeapVariant[]*))
        {
          push(ms,(**listt)[i]);
        }
      else
        {
          assert(false, "ivalid array");
        }

      break;

    case vm.opcode.p_index:
      //wdb("listindex ",ms.evalStack);
      auto index = pop(ms);
      auto list = peek(ms);
      //wdb(list.var);      
      auto i = index.get!int;
      if(auto listt = list.peek!(HeapVariant[]))
        {
          push(ms,(*listt)[i]);
        }
      else if(auto listt = list.peek!(HeapVariant[]*))
        {
          push(ms,(**listt)[i]);
        }
      else
        {
          assert(false, "ivalid array");
        }
      break;

    case vm.opcode.keys:
      //wdb("keys");
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

    case vm.opcode.syncprop:
      // send a setprop message to the client with the contents of the prop
      auto prop = pop(ms).get!string;
      auto obj = pop(ms);
      auto go = obj.get!GameObject;

      if(go.id in vm.universe.objects)
        {
          if(prop in go.props)
            {
              stprop(vm, prop,obj,go.props[prop]);
            }
        }
            
      //       auto val = pop(ms);
      // auto name = pop(ms);
      // auto obj = peek(ms);

      break;
    case vm.opcode.values:
      //wdb("values");
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
      if(auto l = list.peek!(HeapVariant[]))
        {
          auto len =(*l).length;
          push(ms,new HeapVariant(cast(int)len));
        }
      else if(auto l = list.peek!(HeapVariant[]*))
        {
          auto len =(**l).length;
          push(ms,new HeapVariant(cast(int)len));

        }
      else
        {
          assert(false, "expected an array");
        }
      //wdb("listlen ", list, " ", len);
      break;

    case vm.opcode.p_len:
      auto list = peek(ms);
      int len = 0;
      if(auto l = list.peek!(HeapVariant[]))
        {
          len =(*l).length;
        }
      else if(auto l = list.peek!(HeapVariant[]*))
        {
          len = (**l).length;
        }
      else
        {
          assert(false, format("%s invalid array", list.var));
        }
      push(ms,new HeapVariant(cast(int)len));
      //wdb("listlen ", list, " ", cast(int)len);
      break;


    case vm.opcode.genreq: // string -> request on stack
      auto title = pop(ms);
      assert(title.peek!string);
      //wdb("genreq ", title);
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
      // wdb("addaction ", vals[0], vals[1], " : ", req.actions);
      req.actions ~= tuple(vals[0].get!string, vals[1].get!string);
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
         format("{\"t\":\"chat\",\"id\":\"%s\",\"msg\":\"[server] %s\"}",
                clientid, msg.get!string));
      //  writeln("sending say  message to client ", clientid, " " , cm);
      if(vm.isDebug == false)
        {
          vm.zmqThread.send(cm);
        }
      else
        {
          //todo:fire delegate
        }

      break;
    case vm.opcode.suspend: // clientid :: req
      // the first thing we do is copy this entire machine status
      //      writeln("suspendu at ", vm.CurrentMachine.pc);
      vm.machines ~= *vm.CurrentMachine;
      auto newMs = vm.CurrentMachine;
      auto key = pop(newMs);
      assert(key.peek!string);        
      auto clientid = key.get!string;
      auto reqv = pop(newMs);
      assert(reqv.peek!Request);
      auto req = reqv.get!Request;
      string[string] availChoices;
      auto json = toRequestJson(vm, req.title, req.actions, vm.machines.length > 2);
      foreach(x;req.actions)
        {
          availChoices[x[0]]=x[1];
        }

      if(vm.machines.length > 2)
        {
          availChoices["__UNDO__"] = "";
        }
      newMs.validChoices = availChoices;      
      auto cm =
        ClientMessage
        (clientid,
         MessageType.Data,
         json);
      newMs.waitingMessage = new HeapVariant(cm);
      writeln("sending suspend message to client ", clientid, " " , cm);
      if(vm.isDebug == false)
        {
          vm.zmqThread.send(cm);
        }
      else
        {
          //todo:fire delegate
        }

      return true; //wait = Waiting.WaitRequested;

    case vm.opcode.cut:
      // chop the machine stack
      auto current = vm.CurrentMachine;
      vm.machines = [*current];      
      break;

    case vm.opcode.pushscope:
      vm.CurrentMachine.scopes ~= Scope();
      break;

    case vm.opcode.popscope:
      vm.CurrentMachine.scopes = vm.CurrentMachine.scopes[0..$-1];
      break;
      
    case vm.opcode.lambda:
      // lambda will be followed by the function location 
      int loc = readInt(ms,vm);
      Function f;
      f.closureScope = &ms.scopes[$-1];
      f.functionAddress = ms.pc + loc - 5;
      push(ms, new HeapVariant(f));
      wdb(ms.evalStack);
      break;


    case vm.opcode.apply:
      auto arg = pop(ms);
      auto fh = pop(ms);
      if(auto f = fh.peek!Function)
        {
          wdb("exeucting function at", f.functionAddress, " args ", arg);
          Scope s;
          s.closureScope = f.closureScope;
          s.returnAddress = ms.pc;
          ms.scopes ~= s;
          push(ms,arg);                            
          vm.CurrentMachine.pc = f.functionAddress;
        }
      else
        {
          
          assert(false,format("%s : %s not a function value",ms.pc-1, fh));
        }
      
      break;

    case vm.opcode.ret:
      wdb("ret");
      if(ms.scopes.length > 1)
        {
          //walk backwards down the scopes until we find one
          // with a return address
          int index = 1;
          foreach_reverse(ref cf; ms.scopes)
            {
              if(cf.IsFunction)
                {
                  break;
                }
              index++;
            }
          //writeln("returnig ..");
          ms.pc = ms.scopes[$-index].returnAddress;
          //          wdb("pc now ", ms.pc, " call stack length ", ms.callStack.length);
          ms.scopes = ms.scopes[0..$-index];
          //          wdb("pc now ", ms.pc, " call stack length ", ms.callStack.length);
        }
      else
        {
          wdb("end of main function");
          vm.finished = true;
          return true;
        }
            
      break;
    case vm.opcode.shuffle:
      {
        auto list = pop(ms);
        if(auto arr = list.peek!(HeapVariant[]*))
          {
            import std.random : randomShuffle;
            randomShuffle(**arr);
          }
        else
          {
            assert(false, "exepcted an array to shuffle");
          }
        
        break;
        
            
      }
    case vm.opcode.splitat:
      {
        //modifies the list in place, leaving the new
        //list on the heap
        auto bottom = pop(ms).get!bool;
        auto n = pop(ms).get!int;
        auto list = pop(ms);
        if(auto arr = list.peek!(HeapVariant[]*))
          {
            if(bottom)
              {
                //remove from start of list]
                HeapVariant[] newArr;
                newArr = (**arr)[0..n];
                (**arr) = (**arr)[n..$];
                push(ms, new HeapVariant(newArr));
              }
            else
              {
                // remove from top of list
                HeapVariant[] newArr;
                newArr = (**arr)[n..$];
                (**arr) = (**arr)[0..n];
                push(ms, new HeapVariant(newArr));
              }
          }
        else
          {
            assert(false, "expected array");
          }
        break;
      }
    case vm.opcode.sort:
      {
        import std.algorithm : sort;
        bool desc = pop(ms).get!bool;
        auto list = pop(ms);
        if(auto arr = list.peek!(HeapVariant[]*))
          {
            if(desc)
              {
                sort!("a > b")(**arr);
              }
            else
              {
                sort(**arr);
              }
          }
        else
          {
            assert(false, "exepcted an array to sort");
          }
        break;
      }

    case vm.opcode.sortby:
      {
        
        auto key = pop(ms).get!string;
        auto desc = pop(ms).get!bool;
        import std.algorithm : sort;
        auto list = pop(ms);
        
        if(auto arr = list.peek!(HeapVariant[]*))
          {
            bool myComp(HeapVariant x, HeapVariant y) 
            {
              writeln("!!!");
              if( auto xi = x.peek!GameObject)
                {
                  if( auto yi = y.peek!GameObject)
                    {
                      if(key in xi.props && key in yi.props)
                        {
                          if(desc)
                            {
                              return xi.props[key] > yi.props[key];                                  }
                          else
                            {
                              return xi.props[key] < yi.props[key];                                  }
                        }                      
                      else
                        {
                          assert(false, "sorting key not present in both objects");
                        }
                    }
                }
              assert(0, "can only sort game objects");            
            }

            sort!(myComp)(**arr);

          }


        else
          {
            assert(false, "exepcted an array to sort");
          }

        break;
      }
      
    case vm.opcode.dbg:
      auto hv = pop(ms);
      if(auto arr = hv.peek!(HeapVariant[]*))
        {
          write(**arr);
          output(**arr);
        }
      else
        {
          write(hv.var);
          output(hv.var);
        }
      break;
    case vm.opcode.dbgl:
      auto hv = pop(ms);
      if(auto arr = hv.peek!(HeapVariant[]*))
        {
          writeln(**arr);
          output(**arr, "\n");
          
        }
      else
        {
          writeln(hv.var);
          output(hv.var, "\n");
        }
      break;

    default:
      wdb("unknown opcode ", ins);
      assert(0);
    }

  return false;  
}

bool handleResponse(VM* vm, string client, JSONValue response)
{
  writeln("in handle response : ", client, " ", response["id"]);
  if(vm.CurrentMachine.waitingMessage is null || !vm.CurrentMachine.waitingMessage.peek!ClientMessage)
    {
      writeln("waiting message was null");
      writeln("recieved response from unexpected client ", client, "! ignoring ...", response);
      return false;
    }
  ClientMessage cm = vm.CurrentMachine.waitingMessage.get!ClientMessage;  
  if(cm.client != client)
    {
      writeln("recieved response from unexpected client ", client, "! ignoring ...", response);
      return false;
    }
  else
    {
       if(response["id"].type() == JSON_TYPE.STRING)
        {
          wdb("in handle response str");
          auto id = cast(string)response["id"].str;
          if(id !in vm.CurrentMachine.validChoices)
            {
              writeln("recieved an invalid response ", id, " from client ", client);
              return false;
            }
          else if(id == "__UNDO__")
            {
              //revert back to previous machine and continue
              writeln("falling back ... current machine count ", vm.machines.length);
              vm.machines = vm.machines[0..$-2];
              writeln("now ", vm.machines.length);
              writeln("pc now ", vm.CurrentMachine.pc);
              vm.CurrentMachine.pc --;
              return true;
            }
            else
            {
              push(vm.CurrentMachine, new HeapVariant(id));
              vm.CurrentMachine.waitingMessage = null;
              vm.CurrentMachine.validChoices.clear;
              return true;
            }                            
        }
      else
        {
          writeln("received non string response back from client ", client);
          return false;
        }
    }
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
  for(int i = 0; i < len; i++)
    {
      int stringLen = readInt(input, index);
      string s;
      for(int l = 0; l < stringLen; l++)
        {
          s ~= cast(char)input[index++];
        }
      strings[i] ~= s;
    }
  entryPoint = readInt(input,index);
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
  vm.machines ~= MachineStatus();
  wdb("entry point : ", entry);
  vm.machines[0].pc = entry;
  vm.program = outprog;
  vm.machines[0].scopes ~= Scope();
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

// unittest {
//   VM vm = new VM();
//   setupTest(&vm);
//   writeln(vm.strings);
//   while(vm.machines[0].pc < vm.program.length && !vm.finished )
//     {
//       if(step(&vm))
//         {
//           if(!vm.finished)
//             {
//               auto msg = vm.CurrentMachine.waitingMessage.get!ClientMessage;
//               JSONValue j;
//               j["id"]="0";
//               //j["id"]="green-leg";
//               handleResponse(&vm, msg.client, j);
//             }
//         }
//     }
//   writeln("suspended or finished");
//   writeln("Locations count ", vm.universe.locations.length);
//   // foreach(l;vm.universe.locations)
//   //   {
//   //     writeln(l.key);
//   //   }
    
  
//  }


//  unittest {
//   import std.traits;
//   import std.algorithm;
//   auto ops = EnumMembers!(VM.opcode);
//   // [(list 'stvar x)    (flatten (list #x04 (get-int-bytes(check-string x))))]
//   //  [(list 'sub)        #x08]

//   auto special = ["stvar", "p_stvar",  "ldval", "ldvals", "ldvalb", "bne", "bgt", "blt", "beq", "branch", "ldvar", "lambda"];  

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

