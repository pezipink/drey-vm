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

private JSONValue serialize(const Scope* scp)
{
  JSONValue ret;
  return ret;
}

private JSONValue serialize(const HeapVariant* hv)
{
  JSONValue ret;
  return ret;
}

private JSONValue serialize(const MachineStatus* ms)
{
  JSONValue ret = ["pc" : ms.pc];
  JSONValue[] scopes;
  foreach(ref s; ms.scopes)
    {
      
    }
  ret.object["scopes"] = scopes;

  JSONValue[] evalStack;
  foreach(ref hv; ms.evalStack)
    {

    }
  ret.object["evalStack"] = evalStack;
  
  return ret;
}

private void buildGeneralAnnounce( VM vm, JSONValue* j)
{
  JSONValue[] machines;
  foreach(ref m; vm.machines) // todo: chck this foreeach ref!
    {
      machines ~= serialize(&m);
    }  
  j.object["machines"] = machines;
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
      return DebugResponseAction.Send;
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
