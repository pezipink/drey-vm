import std.json;
import std.format;
import std.string;
import std.concurrency;
import std.array;
import std.conv;
import std.stdio;
import vm;

// struct .MachineStatus
// {
//   int pc;
//   Scope[] scopes;
//   HeapVariant[] evalStack;
//   HeapVariant waitingMessage;
//   string[string] validChoices;
//   @property Scope* currentFrame(){ return &scopes[$-1]; }
// }

// struct Scope
// {
//   // this could be a "stack frame" (return address)
//   // a normal lexical scope (some loop)
//   // a "stack frame" might have a closure scope
//   HeapVariant[string] locals;
//   int returnAddress;
//   Scope* closureScope;
//   @property bool IsFunction() { return returnAddress != 0; }
  
// }


private JSONValue serialize(const Scope* scp, GameObject[int] gos)
{
  JSONValue ret = ["returnAddress": scp.returnAddress];
  JSONValue[string] locals;
  foreach(kvp; scp.locals.byKeyValue)
    {
      locals[kvp.key] = serialize(kvp.value, gos);
    }
  
  ret["locals"] = locals;
  return ret;
}

private JSONValue serialize(const HeapVariant hv, GameObject[int] gos)
{
  if(auto v = hv.peek!int)
    {
      JSONValue ret = ["type": "int"];
      ret.object["value"] = *v;
      return ret;
    }
  else if(auto v = hv.peek!bool)
    {
      JSONValue ret = ["type": "bool"];
      ret.object["value"] = *v;
      return ret;
    }
  else if(auto v = hv.peek!string)
    {
      JSONValue ret = ["type": "string"];
      ret.object["value"] = *v;
      return ret;
    }
  else if(auto v = hv.peek!GameObject)
    {
      JSONValue ret = ["type": "go"];
      ret["id"] = v.id;
      auto go = hv.get!GameObject;
      gos[v.id] = cast(GameObject)go;
      return ret;
    }
  else if(auto v = hv.peek!(GameObject*))
    {
      JSONValue ret = ["type": "go*"];
      ret["id"] = (*v).id;
      gos[(*v).id] = cast(GameObject)**v;
      return ret;
    }
  else if(auto v = hv.peek!(HeapVariant[string]))
    {
      JSONValue ret = ["type": "AA"];
      return ret;
    }
    else if(auto v = hv.peek!(HeapVariant[string]*))
    {
      JSONValue ret = ["type": "AA*"];
      return ret;
    }

  else if(auto v = hv.peek!(Function))
    {
      JSONValue ret = ["type": "function"];
      ret["address"] = v.functionAddress;
      return ret;
    }
  else if(auto v = hv.peek!(Location))
    {
      JSONValue ret = ["type": "location"];
      return ret;
    }
  else if(auto v = hv.peek!(LocationReference))
    {
      JSONValue ret = ["type": "locationref"];
      return ret;
    }

  else if(auto v = hv.peek!(HeapVariant[]))
    {
      JSONValue ret = ["type": "array"];
      return ret;

    }
  else if(auto v = hv.peek!(HeapVariant[]*))
    {
      JSONValue ret = ["type": "array*"];
      return ret;
    }
  else if(auto v = hv.peek!(ClientMessage))
    {
      JSONValue ret = ["type": "clientmessage"];
      return ret;
    }

  else
    {
      TypeInfo t = hv.var.type;
      JSONValue ret = ["type": "!!" ~ t.toString];      
      return ret;
    }
}


private JSONValue serialize(const MachineStatus* ms, GameObject[int] gos)
{
  JSONValue ret = ["pc" : ms.pc];
  JSONValue[] scopes;
  foreach(ref s; ms.scopes)
    {
      scopes ~= serialize(&s, gos);
    }
  ret.object["scopes"] = scopes;

  JSONValue[] evalStack;
  foreach(hv; ms.evalStack)
    {
      evalStack ~= serialize(hv, gos);
    }
  ret.object["evalStack"] = evalStack;
  
  return ret;
}

public void buildGeneralAnnounce( VM vm, JSONValue* j)
{
  JSONValue[] machines;
  GameObject[int] gos;
  foreach(ref m; vm.machines) // todo: chck this foreeach ref!
    {
      machines ~= serialize(&m, gos);
    }  
  j.object["machines"] = machines;
  writeln(gos.length);
  GameObject[int] finalGos;
  void aux(GameObject go)
  {
    finalGos[go.id] = go;
    foreach(p;go.props)
      {
        if(p.peek!GameObject)
          {
            aux(p.get!GameObject);
          }
        else if(p.peek!(GameObject*))
          {
            aux(*p.get!(GameObject*));
          }
      }
  }
  foreach(g; gos.values)
    {
      aux(g);
    }
  writeln(finalGos.length);
  JSONValue[] goArray;
  
  foreach(g; finalGos)
    {
      JSONValue goj = ["id": g.id];
      foreach(kvp;g.props.byKeyValue)
        {
          goj[kvp.key] = serialize(kvp.value, gos);
        }
      goArray ~= goj;
    }

  j.object["gameobjects"] = goArray;
}

private void getProgram(const VM vm, JSONValue* j)
{
  
  JSONValue[] bytes;
  foreach(b; vm.program)
    {
      bytes ~= JSONValue(b);
    }
  j.object["program"] = bytes;
  
  string[string] d;
  JSONValue strings = d;
  foreach(kvp; vm.strings.byKeyValue)
    {
      strings.object[kvp.key.to!string] = kvp.value;
    }
  j.object["strings"] = strings;

  import std.traits;
  import std.algorithm;
  auto ops = EnumMembers!(VM.opcode);
  JSONValue[string] opsdict;
  JSONValue jsonOpcodes = opsdict;
  foreach(i,o;ops)
    {
      string op = o.to!string;
      JSONValue current = ["code": o];                                                   
      if( vm.extended.any!(x=>x==op))
        {
          current.object["extended"] = true;
        }
      else
        {
          current.object["extended"] = false;
        }      
      jsonOpcodes.object[op] = current;
    }
  j.object["opcodes"] = jsonOpcodes; 
}

public void setBreakpoint(VM vm, long address)
{
  vm.breakpoints[address] = true;
}

public void clearBreakpoint(VM vm, long address)
{
  vm.breakpoints.remove(address);
}

enum DebugResponseAction
  {
    Announce,
    Send,
    Nothing    
  }

public DebugResponseAction processDebugMessage(VM vm, ClientMessage* message)
{
  auto j = message.json.parseJSON;
  writeln("recieved debug message ", j); 
  auto id = j["id"].integer;
  auto t = j["type"].str; // type
  switch(t)
    {
    case "get-program":
      j["success"] = true;
      getProgram(vm, &j);
      message.json = j.toString;
      //return DebugResponseAction.Send;
      return DebugResponseAction.Announce;
    case "set-breakpoint":
      j["success"] = true;
      auto address = j["address"].integer;
      setBreakpoint(vm, address);
      return DebugResponseAction.Send;
    case "clear-breakpoint":
      j["success"] = true;
      auto address = j["address"].integer;
      clearBreakpoint(vm, address);
      return DebugResponseAction.Send;
    case "step":
      j["success"] = true;
      auto address = j["address"].integer;
      clearBreakpoint(vm, address);
      return DebugResponseAction.Announce;
    default:
      j["success"] = false;
      message.json = j.toString;
      return DebugResponseAction.Nothing;

    } 
}
