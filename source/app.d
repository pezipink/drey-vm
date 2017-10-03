
import std.file;
import std.stdio;
import std.conv;
import std.range;
import std.algorithm;
import std.json;
import std.format;
import std.string;
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
  vm.machines[0].scopes ~= Scope();
  vm.lastHeart = MonoTime.currTime;
  vm.zmqThread = parentId;
  vm.requiredPlayers = 1;
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
              case MessageType.Status:
                {
                  writeln("rcvd status request");
                  // report the pening request if it is for this client
                  if(vm.CurrentMachine.waitingMessage !is null && vm.CurrentMachine.waitingMessage.peek!ClientMessage)
                    {
                      ClientMessage cm = vm.CurrentMachine.waitingMessage.get!ClientMessage;
                      if(cm.client == message.client)
                        {
                          send(parentId, cm);
                        }
                    }
                  else
                    {
                      //todo: send a direct chat message to the requestor indicating either the server is busy
                      //or waiting for a response form a certain player 
                    }
                  break;
                }
              case MessageType.Universe:
                {
                  writeln("rcbd universe request");
                  break;
                }
              case  MessageType.Data:
                {
                  try
                    {
                      auto j = message.json.parseJSON;
                      switch(j["t"].str)
                        {
                        case "chat":
                          if(j["id"].str == "")
                            {
                              writeln(" got chat message ", message.json);
                              foreach(kvp; vm.players.byKeyValue)
                                {
                                  
                                  auto cm =
                                    ClientMessage
                                    (kvp.key,
                                     MessageType.Data,
                                     format("{\"t\":\"chat\",\"id\":\"%s\",\"msg\":\"[all][%s] %s\"}",
                                            kvp.key, kvp.key, j["msg"].str));
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
                                     format("{\"t\":\"chat\",\"id\":\"%s\",\"msg\":\"[%s] %s\"}",
                                            id, id, j["msg"].str));
                                  //writeln("individualmessage ", cm);
                                  parentId.send(cm);
                                }
                              else
                                {
                                  writeln("! ", j["id"].str);
                                  auto cm =
                                    ClientMessage
                                    (message.client,
                                     MessageType.Data,
                                     "{\"t\":\"chat\",\"id\":\"server\",\"msg\":\"No player exists with that name. \"}");                         
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
                          else
                            {
                              writeln("continuing ...");
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





import dlangui;
import dlangui.widgets.tree;



enum IDEActions : int {
  FileOpen = 1,
    DebuggerStep,
    SetBreakpoint,
    DebuggerRun,
    GotoLocation
}

// actions
const Action ACTION_FILE_OPEN = new Action(IDEActions.FileOpen, "MENU_FILE_OPEN"c, "document-open", KeyCode.KEY_O, KeyFlag.Control);

const Action ACTION_STEP = new Action(IDEActions.DebuggerStep, "DEBUGGER_STEP"c, "debugger-step", KeyCode.F10, 0);

const Action ACTION_RUN = new Action(IDEActions.DebuggerRun, "DEBUGGER_RUN"c, "debugger-run", KeyCode.F5, 0);

const Action ACTION_SET_BREAKPOINT = new Action(IDEActions.SetBreakpoint, "SET_BREAKPOINT"c, "set-breakpoint", KeyCode.F9, 0);

const Action ACTION_GOTO_LOCATION = new Action(IDEActions.GotoLocation, "GOTO_LOCATION"c, "goto-location", KeyCode.F1, 0);

import dlangui.dialogs.filedlg;
import dlangui.dialogs.dialog;

class DreyFrame : AppFrame {

    MenuItem mainMenuItems;

  
    override protected void initialize() {
        _appName = "Drey VM";
        super.initialize();
        if(statusLine)
          {
            statusLine.setStatusText("Drey VM");
          }
        loadScurry("c:\\temp\\test.scur");
        postExecution();
    }

    /// create main menu
    override protected MainMenu createMainMenu() {
        mainMenuItems = new MenuItem();
        MenuItem fileItem = new MenuItem(new Action(1, "MENU_FILE"));
        fileItem.add( ACTION_FILE_OPEN);
        fileItem.add( ACTION_STEP);
        fileItem.add( ACTION_SET_BREAKPOINT);
        fileItem.add( ACTION_RUN);
        fileItem.add( ACTION_GOTO_LOCATION);
        mainMenuItems.add(fileItem);
        MainMenu mainMenu = new MainMenu(mainMenuItems);
        return mainMenu;
    }


    /// create app toolbars
    override protected ToolBarHost createToolbars() {
        ToolBarHost res = new ToolBarHost();
        ToolBar tb;
        tb = res.getOrAddToolbar("Standard");
        tb.addButtons( ACTION_FILE_OPEN);
        return res;
    }

    string _filename;
    void openSourceFile(string filename) {
        import std.file;
        if (exists(filename)) {
            // _filename = filename;
            // window.windowCaption = toUTF32(filename);
            // _editor.load(filename);
            // updatePreview();
        }
    }

    bool onCanClose() {
        // todo
        return true;
    }

    FileDialog createFileDialog(UIString caption, bool fileMustExist = true) {
        uint flags = DialogFlag.Modal | DialogFlag.Resizable;
        if (fileMustExist)
            flags |= FileDialogFlag.FileMustExist;
        FileDialog dlg = new FileDialog(caption, window, null, flags);
        //        dlg.filetypeIcons[".scr"] = "text-dml";
        return dlg;
    }

  protected VM _vm = new VM();

  void refreshTree()
  {
    TreeWidget root = cast(TreeWidget)childById("DreyRoot");
    
    //TreeItem tree1 = tree.items.newChild("group1", "Group 1"d, "document-open");
    //    tree1.newChild("g1_1", "Group 1 item 1"d);

  }
  void showInstruction(int number)
  {
    auto text = format("%X",number+1).to!dstring;
    showInstruction(text);
  }

  void showInstruction(dstring number)
  {
    if(number in _rowLookup)
      {        
        _grid.makeCellVisible(3, _rowLookup[number]+10);
        _grid.selectCell(3, _rowLookup[number]+1, true);
      }
  }

  void ss(string s)
  {
    statusLine.setStatusText(s.to!dstring);
  }
  void ss(dstring s)
  {
    statusLine.setStatusText(s);
  }


  
  TreeItem _selectedTree = null;
  TreeItem _selectedClientTree = null;

  void PushScope()
  {
    int max = _vm.CurrentMachine.scopes.length;
    TreeWidget root = childById!TreeWidget("DreyRoot");
    TreeItem preserve = _selectedTree;
    assert(root, "root not found");
    ss("push");
    // root.items.newChild("dskd","WTF"d);
    // _selectedTree.newChild("dskjdkfjkdd","WTF"d);
    auto parent = root.items.findItemById("machine0scopes");
    assert(parent, "could not find scopes parent");

    //    ss(format("found parent, max is %s", max));
    string s1 = format("machine0scope%s",max-1);
    auto s2 = format("Scope %s",max-1).to!dstring;

   
    TreeItem newNode = _scopes.newChild(s1, s2, null);

    // adding causes the selection to be dropped so re-select it
    if(preserve !is null)
      {
        root.selectItem(preserve,true);
      }
    invalidate();

  }

  void PopScope()
  {
    int max = _vm.CurrentMachine.scopes.length;
    TreeWidget root = childById!TreeWidget("DreyRoot");
    TreeItem preserve = _selectedTree;
    string id = format("machine0scope%s",max);
    auto tr = root.items.findItemById(id);
    auto parent = cast(TreeItem)tr.parent;
    parent.removeChild(id);
    // //removing causes the selection to be dropped so re-select it
    // if(preserve !is null && preserve.parent is parent)
    //   {
    //     root.selectItem(preserve,true);
    //   };
  }
  void updateClientViewer()
  {
    TreeWidget root = childById!TreeWidget("clienttree");
    auto resps = root.findItemById("client1responses");            
    if(_vm.CurrentMachine.waitingMessage !is null && resps.childCount == 0 )
      {
        // todo: assuming everything is for client 1 for now
        foreach(kvp; _vm.CurrentMachine.validChoices.byKeyValue)
          {
            TreeItem x = resps.newChild(kvp.key, kvp.value.to!dstring);
            x.objectParam = new HeapVariant(kvp.key);                    
          }
      }
       
    // if(_selectedClientTree)
    //   {
    //     if(_selectedClientTree.id == "client1responses")
    //       {
    //       }

    //   }
  }
  void updateViewer()
  {
    if(_selectedTree)
      {
        
        auto sthing = cast(StringListWidget)childById("stringthing");
        ss(_selectedTree.id);
        if(_selectedTree.id == "universeobjects")
          {
            dstring[] items;
            foreach(okvp;_vm.universe.objects.byKeyValue)
              {
                string s = okvp.key.to!string;
                auto s2 = okvp.value.props.byKeyValue.map!(x=>format("%s:%s",x.key, x.value)).join(", ") ;
                items ~= format("%s>%s",s,s2).to!dstring;
              }
                
            sthing.items=items;
          }
    
        else if(_selectedTree.id.startsWith("machine0stack"))
          {
            auto items = _vm.CurrentMachine.evalStack.map!(x=>format("%s",x).to!dstring).array;
            sthing.items = items;
          }
        else if(_selectedTree.id.startsWith("machine0scope"))
          {
            if(_selectedTree.id == "machine0scopes")
              {
                int scopeIndex = 0;
                dstring[] items;
                foreach(scp; _vm.CurrentMachine.scopes)
                  {
                    foreach(kvp; scp.locals.byKeyValue)
                      {
                        items ~= format("%s>%s:%s", scopeIndex, kvp.key, kvp.value).to!dstring;
                      }
                    scopeIndex++;        
                  }
                sthing.items = sort(items).array;
              }
            else 
              {
                try
                  {
                    string s = _selectedTree.id[$-1..$];
                    int id = parse!int(s);
                    if(_vm.CurrentMachine.scopes.length > id)
                      {
                        auto items =
                          _vm.CurrentMachine.scopes[id].locals
                          .byKeyValue                          
                          .map!(x=>format("%s => %s",x.key, x.value).to!dstring)
                          .array;
                        sthing.items = sort(items).array;
                      }
                  }
                catch(Exception ex)
                  {
                    ss(ex.msg);
                  }
              }
          }

      }
    else
      {
        //        ss("not selected");
      }
  }
  
  void postExecution()
  {
    // update all the things here
    //   ss(format("vm now at instruction %s count %s", _vm.CurrentMachine.pc, stepount));
    showInstruction(_vm.CurrentMachine.pc);
    _grid.updateExec(_vm.CurrentMachine.pc);
    // 1.  show the currently executing instruction
    // 2.  update the tree views??
    // 3.  update whatever has context based on tree selection
    updateViewer();
    invalidate();
  }
  
  void loadScurry(string fileName)
  {
    _vm.Initialize(fileName);
    _vm.isDebug = true;
    _vm.AddPlayer("A");

    int row = 0;
    int index = 0;
    ubyte readByte()
    {
      auto res = _vm.program[index];
      index++;
      return res;
    }

    short readWord()
    {
      ushort res = readByte() << 8;
      res |= readByte();
      return res;
    }

    int readInt()
    {
      int res = readWord() << 16;
      res |= readWord();
      return res;
    }

    dstring getString()
    {
      auto lookup = readInt();
      return _vm.strings[lookup].to!dstring;
    }

    //iterating the program twice just to size and populate
    //the grid isnt very nice but whatevs, itll do for now
    while(index < _vm.program.length)
      {
        VM.opcode op = cast(VM.opcode)readByte();
        switch(op)
          {
          case VM.opcode.stvar:
          case VM.opcode.p_stvar:
          case VM.opcode.ldvals:
          case VM.opcode.ldvar:
            getString();
            break;
          case VM.opcode.ldval:
          case VM.opcode.bne:
          case VM.opcode.bgt:
          case VM.opcode.blt:
          case VM.opcode.beq:
          case VM.opcode.branch:
          case VM.opcode.lambda:
            readInt();
            break;
          case VM.opcode.ldvalb:
            readInt();
            break;
          default:
            break;
          
          }
        row++;
      }
    _grid.resize(5,row);
    index = 0;
    row=0;

    while(index < _vm.program.length)
      {
        VM.opcode op = cast(VM.opcode)readByte();
        dstring hex = format("%X", index).to!dstring;
        _grid.setCellText(0,row,hex);
        _rowLookup[hex] = row;
        _grid.setCellText(2,row, format("%s", op).to!dstring);
        switch(op)
          {
          case VM.opcode.stvar:
          case VM.opcode.p_stvar:
          case VM.opcode.ldvals:
          case VM.opcode.ldvar:
            _grid.setCellText(3,row, getString());
            break;
          case VM.opcode.ldval:
            _grid.setCellText(3,row, readInt().to!dstring);
            break;
          case VM.opcode.bne:
          case VM.opcode.bgt:
          case VM.opcode.blt:
          case VM.opcode.beq:
          case VM.opcode.branch:
          case VM.opcode.lambda:
            int address = readInt();
            int actualAddress = index + address - 4;
            dstring text = format("%X",actualAddress).to!dstring;
            _grid.setCellText(3,row, text);
            break;
          case VM.opcode.ldvalb:
            bool b = readInt() != 0;
            _grid.setCellText(3,row, b.to!dstring);
            break;
          default:
            break;
          
          }

        row++;
      }

    _grid.autoFit();


  }
  
    void saveAs() {
    }
  int stepCount = 0;
    /// override to handle specific actions
    override bool handleAction(const Action a) {
      if (a) {
        switch (a.id) {
        case IDEActions.GotoLocation:
          import dlangui.dialogs.inputbox;
          auto idlg =
            new InputBox
            (UIString.fromRaw("Goto"),UIString.fromRaw("Goto"),_window, "Enter location in hex"d,
             delegate(dstring res) {
              if(res !is null && res != ""d)
                {
                  showInstruction(res.toUpper);
                }
            });
          idlg.show();
          return true;
        case IDEActions.FileOpen:
          UIString caption;
          caption = "Open DML File"d;
          FileDialog dlg = createFileDialog(caption);
          dlg.addFilter(FileFilterEntry(UIString("Scurry files"d), "*.scur"));
          dlg.addFilter(FileFilterEntry(UIString("All files"d), "*.*"));
          dlg.dialogResult = delegate(Dialog dlg, const Action result) {
            if (result.id == ACTION_OPEN.id) {
              string filename = result.stringParam;
              loadScurry(filename);
              statusLine.setStatusText("Program loaded."d);
            }
          };
          dlg.show();
          return true;
        case IDEActions.SetBreakpoint:
          auto text =_grid.cellText(0,_grid.row);
          ss(text);
          int index = parse!int(text,16);
          _breakpoints[index] = 0;
          _grid.setBreakpoint(index);
          return true;
        case IDEActions.DebuggerRun:
          auto oc = peekOpcode(&_vm);
          try
            {
              while(_vm.CurrentMachine.pc+1 !in _breakpoints
                    //                    && _vm.CurrentMachine.pc+1 < _vm.program.length
                    && _vm.CurrentMachine.waitingMessage is null)
                {
                  oc = peekOpcode(&_vm);
                  step(&_vm);
                  stepCount++;
                  switch(oc)
                    {
                    case VM.opcode.apply:
                      PushScope();
                      break;
                    case VM.opcode.ret:
                      PopScope();
                      break;
                    default:
                      break;
                    }
                  if(oc == VM.opcode.brk)
                    {
                      break;
                    }


                }
              if(_vm.CurrentMachine.waitingMessage !is null)
                {
                  ss("Cannot step - waiting on client response");
                  updateClientViewer();
                }

            }
          catch(Throwable e)
            {
              ss("Exception occured: " ~ e.msg);
            }
          postExecution();
          return true;
        case IDEActions.DebuggerStep:
          if(_vm.CurrentMachine.waitingMessage !is null)
  
            {
              ss("Cannot step - waiting on client response or program terminated.");
              updateClientViewer();
              return true;
            }
          auto oc = peekOpcode(&_vm);
          step(&_vm);
          stepCount++;
          switch(oc)
            {
            case VM.opcode.apply:
              PushScope();
              break;
            case VM.opcode.ret:
              PopScope();
              break;
            default:
              break;
            }
          postExecution();
          return true;
        default:
          return super.handleAction(a);
        }
      }
      return false;
    }

 /// override to handle specific actions state (e.g. change enabled state for supported actions)
    override bool handleActionStateRequest(const Action a) {
        switch (a.id) {
            case IDEActions.FileOpen:
                a.state = ACTION_STATE_ENABLED;
                return true;
            case IDEActions.DebuggerStep:
                a.state = ACTION_STATE_ENABLED;
                return true;
        default:
                return super.handleActionStateRequest(a);
        }
    }

    void updatePreview() {
        // dstring dsource = _editor.text;
        // string source = toUTF8(dsource);
        // try {
        //     Widget w = parseML(source);
        //     if (statusLine)
        //         statusLine.setStatusText("No errors"d);
        //     if (_fillHorizontal)
        //         w.layoutWidth = FILL_PARENT;
        //     if (_fillVertical)
        //         w.layoutHeight = FILL_PARENT;
        //     if (_highlightBackground)
        //         w.backgroundColor = 0xC0C0C0C0;
        //     _preview.contentWidget = w;
        // } catch (ParserException e) {
        //     if (statusLine)
        //         statusLine.setStatusText(toUTF32("ERROR: " ~ e.msg));
        //     _editor.setCaretPos(e.line, e.pos);
        //     string msg = "\n" ~ e.msg ~ "\n";
        //     msg = replaceFirst(msg, " near `", "\nnear `");
        //     TextWidget w = new MultilineTextWidget(null, toUTF32(msg));
        //     w.padding = 10;
        //     w.margins = 10;
        //     w.maxLines = 10;
        //     w.backgroundColor = 0xC0FF8080;
        //     _preview.contentWidget = w;
        // }
    }

  protected bool _fillHorizontal;
  protected bool _fillVertical;
  protected bool _highlightBackground;
  protected ScrollWidget _preview;
  protected int[dstring] _rowLookup;
  protected int[int] _breakpoints;
  private TreeItem _scopes;


  protected DisassemblyGrid _grid;
    /// create app body widget
    override protected Widget createBody() {
        VerticalLayout bodyWidget = new VerticalLayout();
        bodyWidget.layoutWidth = FILL_PARENT;
        bodyWidget.layoutHeight = FILL_PARENT;
        HorizontalLayout hlayout = new HorizontalLayout();
        hlayout.layoutWidth = FILL_PARENT;
        hlayout.layoutHeight = FILL_PARENT;
        _grid = new DisassemblyGrid();
         _grid.layoutHeight(FILL_PARENT);
        _grid.layoutWidth(FILL_PARENT);
        _grid.layoutWidth = 800;
        _grid.layoutWeight = 25;
        //        _grid.layoutWidth = makePercentSize(50);
        _grid.showColHeaders = true;
        _grid.showRowHeaders = true;
        _grid.resize(5, 50);
        _grid.fixedCols = 3;
        _grid.fixedRows = 0;
        _grid.rowSelect = true; // testing full row selection
        _grid.selectCell(4, 6, false);

        class Handler : CellActivatedHandler, OnKeyHandler, OnTreeSelectionChangeListener
        {
          void onTreeItemSelected(TreeItems source, TreeItem selectedItem, bool activated)
          {

            _selectedTree = selectedItem;
            updateViewer();
          }

          void onCellActivated(GridWidgetBase source, int col, int row)
          {
            auto text = _grid.cellText(col,row);
            if(text in _rowLookup)
              {
                _grid.makeCellVisible(3, _rowLookup[text]+1);
                _grid.selectCell(3, _rowLookup[text]+1, true);
              }
          }
          bool onKey(Widget source, KeyEvent event)
          {
            //            statusLine.setStatusText("in onKey");
            return false;
          }
        }
        class ClientHandler : OnKeyHandler, OnTreeSelectionChangeListener
        {
          void onTreeItemSelected(TreeItems source, TreeItem selectedItem, bool activated)
          {
            _selectedClientTree = selectedItem;
            updateClientViewer();
          }
          bool onKey(Widget source, KeyEvent event)
          {
            if(event.keyCode == KeyCode.RETURN && _selectedClientTree !is null)
              {
                if( _selectedClientTree.objectParam !is null)
                  {
                      HeapVariant hv = cast(HeapVariant)_selectedClientTree.objectParam;
                      JSONValue js;
                      js["t"] = "response";
                      js["id"] = hv.get!string ;
                      ss("sent response " ~ js["id"].str);
                      handleResponse(&_vm, "A", js);
                      _selectedClientTree = null;
                      TreeWidget root = childById!TreeWidget("clienttree");
                      auto resps = root.findItemById("client1responses");
                      resps.clear();
                      ss("count is now " ~ resps.childCount.to!string);
                      invalidate();
                  }
                
              }
            return false;
          }
        }

        Handler h = new Handler();
        _grid.cellActivated = h;
        _grid.keyEvent = h;

        VerticalLayout vlayout = new VerticalLayout();
        vlayout.layoutWidth = FILL_PARENT;
        vlayout.layoutHeight = FILL_PARENT;
        //        vlayout.layoutWeight = 15;
       
        TreeWidget tree = new TreeWidget("DreyRoot");
        
        TreeItem tree2 = tree.items.newChild("machinesroot", "Machines"d, "document-open");
        auto machine0 = tree2.newChild("machine0", "Machine 0"d, null);
        machine0.newChild("machine0stack", "Stack", null);
        TreeItem scopes = machine0.newChild("machine0scopes", "Scopes", null);
        _scopes = scopes;
        scopes.newChild("machine0scope0","Scope 0", null);
        
        TreeItem tree3 = tree.items.newChild("universeroot", "Universe"d, "document-open");
        tree3.newChild("universeobjects", "Objects"d);
        tree3.newChild("universelocations", "Locations"d);
        tree3.newChild("universelocationrefs", "LocationRefs"d);

        tree.selectionChange = h;

        TabWidget tabs = new TabWidget("tabs");
        
        TreeWidget clients = new TreeWidget("clienttree");
        ClientHandler h2 = new ClientHandler;
        clients.selectionChange = h2;
        clients.keyEvent = h2;
        auto cs = clients.items.newChild("clientroot", "Clients"d);
        auto c1 = cs.newChild("client1", "Client 1");
        c1.newChild("client1responses", "Available Responses");
        
        auto popup = new MenuItem();
         auto stringthing = new StringListWidgetWithPopup("stringthing", statusLine);
        auto menu = new MenuItem(null);
        menu.add(ACTION_STEP);
        stringthing.popupMenu = menu;
        stringthing.gotoInstruction =  num => showInstruction(num);
        tree.layoutWidth(FILL_PARENT);       
        tree.layoutHeight(FILL_PARENT);
        stringthing.itemClick = delegate (Widget source, int index) {
          //          ss(stringthing.selectedItem);
          stringthing.showPopupMenu(0,0);

          return true;
          };
        //      auto debugStringThing = new StringListWidget("debugstringthing");
        auto debugStringThing = new MultilineTextWidget("debugstringthing");
        //        debugStringThing.
        ScrollWidget scroll = new ScrollWidget("outputscroller");

        scroll.contentWidget = debugStringThing;
        
        vm.debugOutput =
          delegate (string msg)
          {
            ss(msg);
            //            string x = "\n" ~ msg;
            string x = msg;
            //            debugStringThing.text = x.to!dstring ~ debugStringThing.text ;
            debugStringThing.text = debugStringThing.text ~ x.to!dstring ;
            return;
          };
        auto t1 = tabs.addTab(stringthing, "Inspector"d);
        auto t2 = tabs.addTab(clients, "Clients"d);
        auto t3 = tabs.addTab(scroll, "Output"d);
        vlayout.addChild(tree);
        vlayout.addChild(new ResizerWidget());
        
        vlayout.addChild(tabs);
        
        //        tree.layoutWidth = makePercentSize(50); 
        tree.layoutWidth(FILL_PARENT);       
        tree.layoutHeight(FILL_PARENT);
        tabs.layoutWidth(FILL_PARENT);       
        tabs.layoutHeight = makePercentSize(75);
        
        // tree.layoutWeight = 50;
        hlayout.addChild(_grid);
        hlayout.addChild(new ResizerWidget());
        //        vlayout.layoutWeight = 50;
        hlayout.addChild(vlayout);

        bodyWidget.addChild(hlayout);

        return bodyWidget;
    }

}



mixin APP_ENTRY_POINT;

__gshared  Window window;
/// entry point for dlangui based application
extern (C) int UIAppMain(string[] args) {

  // create window  
   window = Platform.instance.createWindow("Drey Virtual Machine"d, null, WindowFlag.Resizable, 700, 470);

    
  auto btn = (new Button("btn1", "Button 1"d)).padding(5).margins(10).textColor(0xFF0000).fontSize(30);
  btn.click = delegate(Widget src) {
    src.text = "clicking";

    return true;
  };

  auto root = new DreyFrame();

  // create some widget to show in window
  window.mainWidget = root;


  // show window
  window.show();
  window.setWindowState( WindowState.maximized);
    // run message loop
  return Platform.instance.enterMessageLoop();
}

class StringListWidgetWithPopup : StringListWidget
{

  MenuItem _popupMenu;
  void delegate(int) _showInstruction;
  StatusLine _status;
  this(string id, StatusLine status)
  {
    _status = status;
    super(id);
  }
  @property MenuItem popupMenu() {
    return _popupMenu;
  }

  @property void popupMenu(MenuItem popupMenu) {
    _popupMenu = popupMenu;
  }

  @property void gotoInstruction(void delegate(int number) func) {
    _showInstruction = func;
  }
  void PopulateActions()
  {
    if(selectedItem is null)
      {
        _status.setStatusText("sel item was null"d);
        return;
      }
    _popupMenu = new MenuItem();
    // parse selected item text and add actions to jump to functions / game objects etc
    auto text = selectedItem ~ " "d;
    _status.setStatusText("parsing"d ~ text);

     int count = 0;
  string[] results;
  while(1)
    {
      import std.ascii;
      // find F:12DEF  function hexes
      auto split = text.findSplitAfter("F:");
      if(split[0] == "")
        {
          break;
        }

      // try to extract hex
      char c;
      string hex;
      auto toParse = split[1];
      int i = 0;
      int actionId = 0;
      while(i < toParse.length)
        {
          c = toParse[i].to!char;
          if(c.isHexDigit)
            {
              hex~=c;
            }
          else if(c == ' ' || c == '\n')
            {
              if(hex.length > 0)
                {
                  string lab = "Goto function at " ~ hex;
                  Action a = new Action(actionId++, lab.to!dstring);
                  a.stringParam = "function";
                  a.longParam = parse!long(hex,16);
                  _status.setStatusText(lab.to!dstring);
                  _popupMenu.add(a);
                }
              break;
            }
          i++;
        }
      
      text = split[1];
    }

    
  }
  
  override void showPopupMenu(int x, int y) {
    /// if preparation signal handler assigned, call it; don't show popup if false is returned from handler
    if (_popupMenu.openingSubmenu.assigned)
      if (!_popupMenu.openingSubmenu(_popupMenu))
        return;

    PopulateActions();
    PopupMenu popupMenu = new PopupMenu(_popupMenu);
    popupMenu.menuItemAction.connect
      (delegate(const Action action)
       {
         if(action.stringParam == "function")
           {
             _showInstruction(action.longParam.to!int);
           }

         return true;
       });
    PopupWidget popup = window.showPopup(popupMenu, this);
    popup.flags = PopupFlags.CloseOnClickOutside;
  }

}

class DisassemblyGrid : StringGridWidget
{
  private int[int] breakpoints;
  private int exeLoc;
  uint bpColour;
  uint exeColour;
  this()
  {
    bpColour = decodeHexColor("red", 0x000000);
    exeColour = decodeHexColor("blue", 0x000000);
    
  }

  public void updateExec(int row)
  {
    exeLoc = row + 1;
  }
  
  public void setBreakpoint(int row)
  {
    if(row in breakpoints)
      {
        breakpoints.remove(row);
      }
    else
      {
        breakpoints[row]=1;
      }
  }
  
  protected override void drawCell(DrawBuf buf, Rect rc, int col, int row)
  {
    auto text = cellText(0,row);
    auto id = parse!int(text,16);
    
    if (_customCellAdapter && _customCellAdapter.isCustomCell(col, row)) {
      return _customCellAdapter.drawCell(buf, rc, col, row);
    }
    if (BACKEND_GUI) 
      rc.shrink(2, 1);
    else 
      rc.right--;
    FontRef fnt = font;
    dstring txt = cellText(col, row);
    Point sz = fnt.textSize(txt);
    Align ha = Align.Left;
    //if (sz.y < rc.height)
    //    applyAlign(rc, sz, ha, Align.VCenter);
    int offset = BACKEND_CONSOLE ? 0 : 1;
    if(id == exeLoc)
      {
        fnt.drawText(buf, rc.left + offset, rc.top + offset, txt, exeColour);       
      }
    else if(id in breakpoints)
      {
        fnt.drawText(buf, rc.left + offset, rc.top + offset, txt, bpColour);       
      }
    else
      {
        fnt.drawText(buf, rc.left + offset, rc.top + offset, txt, textColor);
      }
 
  }
}

// void main()
// {
//   // Prepare our context and sockets
//   writeln( "start");
//   auto server = Socket(SocketType.router);
//   writeln("bdining socket");
//   server.bind("tcp://*:5560");

//   // Initialize poll set
//   auto items = [
//                 PollItem(server, PollFlags.pollIn),
//                 ];
//   writeln("spawning server...");
//   auto worker = spawn(&Server, thisTid);
    
//   // Switch messages between sockets
//   while (true) {
//     Frame frame;
//     ClientMessage message;

//     if(!receiveTimeout
//        (dur!"msecs"(1),
//         (ClientMessage msg)
//         {
//           server.send(msg.client,true);
//           ubyte[] data = [cast(ubyte)msg.type];

//           if(msg.type == MessageType.Data)
//             {
//               server.send(data,true);
//               //writeln("sending json ", msg.json);
//               server.send(msg.json);
//             }
//           else
//             {
//               server.send(data);
//             }

//         },
          
//         (Variant  any) { writeln("unexpected msg ", any);}
//         ))
//       {
//         poll(items, dur!"msecs"(1));
//         if (items[0].returnedEvents & PollFlags.pollIn) {            
//           bool invalidMessage = false;
//           /// first frame will be the id
//           frame.rebuild();
//           server.receive(frame);
//           string client = frame.data.asString;
//           //            writeln("identifier ", client);
//           message.client = client.dup;
//           if(frame.more)
//             {
//               frame.rebuild();
//               server.receive(frame);
//               // see what sort of message this is
//               message.type = cast(MessageType)frame.data[0];
//             }
//           //            writeln("message type ", message.type);
//           if(frame.more)
//             {
//               if(message.type == MessageType.Data)
//                 {
//                   frame.rebuild();
//                   server.receive(frame);
//                   message.json = frame.data.asString.dup;
//                   send(worker, message);
//                   //                    writeln("sent message to worker ", message);
//                 }
//               else
//                 {                
//                   //bad message, swallow it up
//                   invalidMessage = true;
//                   do {
//                     frame.rebuild();
//                     server.receive(frame);
//                   } while (frame.more);
//                   writeln("invalid message received");
//                 }

//             }
//           else
//             {
//               send(worker, message);
//             }
//         }
//       }
        
//   }
// }
