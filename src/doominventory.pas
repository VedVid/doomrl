{$INCLUDE doomrl.inc}
unit doominventory;
interface
uses SysUtils,
     vnode,
     dfitem, dfthing, dfdata,
     doomcommand, doomhooks;

type
  TItemList      = array[TItemSlot] of TItem;
  TEquipmentList = array[TEqSlot] of TItem;

TInventory = class;

TInventoryEnumerator = specialize TGNodeEnumerator< TItem >;

TInventory = class( TVObject )
       constructor Create( aOwner : TThing );
       procedure Sort( var aList : TItemList );
       function  Size : byte;
       procedure Add( aItem : TItem );
       function  SeekAmmo( aAmmoID : DWord ) : TItem;
       function  DoScrollSwap : TCommand;
       function  AddAmmo( aAmmoID : DWord; aCount : Word ) : Word;
       function  isFull : boolean;
       procedure RawSetSlot( aIndex : TEqSlot; aItem : TItem ); inline;
       procedure EqSwap( aSlot1, aSlot2 : TEqSlot );
       procedure EqTick;
       procedure ClearSlot( aItem : TItem );
       function DoWear( aItem : TItem ) : Boolean;
       // no checking if slot fits!
       function DoWear( aItem : TItem; aSlot : TEqSlot ) : Boolean;
       function Wear( aItem : TItem ) : Boolean;
       function Contains( aItem : TItem ) : Boolean;
       function FindSlot( aItem : TItem ) : TEqSlot;
       function GetEnumerator : TInventoryEnumerator;
       function Equipped( aItem : TItem ) : Boolean;
       destructor Destroy; override;
       procedure setSlot( aIndex : TEqSlot; aItem : TItem ); inline;
     private
       FOwner  : TThing;
       FChosen : TItem;
       FSlots  : TEquipmentList;
       function  getSlot( aIndex : TEqSlot ) : TItem; inline;
     public
       property Slot[ aIndex : TEqSlot ] : TItem read getSlot;
     end;

implementation

uses vmath, vgenerics, vluasystem, doomio, doomkeybindings, dfplayer;

{ TInventoryEnumerator }

function TInventory.Wear( aItem : TItem ) : Boolean;
begin
  if aItem = nil then Exit( False );
  if not Contains( aItem ) then Exit( False );
  if not aItem.isWearable then Exit( False );
  setSlot( aItem.eqSlot, aItem );
  Exit( True )
end;

function TInventory.getSlot(aIndex: TEqSlot): TItem; inline;
begin
  Exit(FSlots[aIndex]);
end;

procedure TInventory.setSlot( aIndex: TEqSlot; aItem: TItem); inline;
begin
  if FSlots[aIndex] = aItem then Exit;
  if FSlots[aIndex] <> nil  then FSlots[aIndex].CallHook( Hook_OnRemove, [FOwner] );
  FSlots[aIndex] := nil;
  if aItem <> nil then aItem.CallHook( Hook_OnEquip, [FOwner] );
  if aItem <> nil then FOwner.Add( aItem );
  FSlots[aIndex] := aItem;
end;

procedure TInventory.RawSetSlot( aIndex: TEqSlot; aItem: TItem ); inline;
begin
  if aItem <> nil then FOwner.Add( aItem );
  FSlots[aIndex] := aItem;
end;

constructor TInventory.Create( aOwner : TThing );
var iSlot : TEqSlot;
begin
  FChosen := nil;
  FOwner  := aOwner;
  for iSlot in TEqSlot do
    FSlots[iSlot] := nil;
end;

function TInventory.Size : byte;
var iSlot : TEqSlot;
begin
  Size := FOwner.ChildCount;
  for iSlot in TEqSlot do
    if FSlots[iSlot] <> nil then
      Dec(Size);
end;

procedure TInventory.Add( aItem : TItem );
begin
  if aItem = nil then Exit;
  if isFull then raise EItemException.Create('Inventory full at add!');
  FOwner.Add( aItem );
end;

destructor TInventory.Destroy;
begin
end;

procedure   TInventory.Sort( var aList : TItemList );
var iCount  : Integer;
    iCount2 : Integer;
begin
  for iCount := Low(TItemSlot) to High(TItemSlot)-Low(TItemSlot) do
    for iCount2 := Low(TItemSlot) to High(TItemSlot)-iCount do
      if TItem.Compare(aList[iCount2],aList[iCount2+1]) then
        SwapItem(aList[iCount2],aList[iCount2+1]);
end;

function TInventory.SeekAmmo( aAmmoID : DWord ) : TItem;
var iAmmo      : TItem;
    iAmmoCount : Integer;
begin
  SeekAmmo   := nil;
  iAmmoCount := 65000;

  for iAmmo in Self do
     if iAmmo.isAmmo then
       if iAmmo.NID = aAmmoID then
       if iAmmo.Ammo <= iAmmoCount then
       begin
         SeekAmmo   := iAmmo;
         iAmmoCount := iAmmo.Ammo;
       end;
end;

type TItemArray = specialize TGObjectArray< TItem >;

function TInventory.DoScrollSwap : TCommand;
var iArray   : TItemArray;
    iItem    : TItem;
    iIdx     : Integer;
    iInput   : TInputKey;
begin
  DoScrollSwap.Command := COMMAND_NONE;
  iArray := TItemArray.Create( False );
  if Slot[ efWeapon ]  <> nil then
  begin
    iArray.Push( Slot[ efWeapon ] );
    if Slot[ efWeapon ].Flags[ IF_CURSED ] then
    begin
      IO.Msg('You can''t!');
      FreeAndNil( iArray );
      Exit;
    end;
  end;
  if (Slot[ efWeapon2 ] <> nil) and Slot[ efWeapon2 ].isWeapon then iArray.Push( Slot[ efWeapon2 ] );
  for iItem in Self do
    if not Equipped( iItem ) then
      if iItem.isWeapon then
        iArray.Push( iItem );

  if iArray.Size = 0 then IO.Msg('You have no weapons!');
  if iArray.Size = 1 then IO.Msg('You have no other weapons!');
  if iArray.Size > 1 then
  begin
    IO.Msg('Use @<scroll@> to choose weapon, @<left@> button to wield, @<right@> to cancel...');
    iIdx := 1;
    if Slot[ efWeapon ] = nil then iIdx := 0;
    repeat
      IO.SetHint( iArray[iIdx].Description );
      iInput := IO.WaitForInput( [INPUT_MSCRUP,INPUT_MSCRDOWN,INPUT_MLEFT,INPUT_MRIGHT,INPUT_ESCAPE,INPUT_OK] );
      if iInput = INPUT_MSCRUP   then if iIdx = 0 then iIdx := iArray.Size-1 else iIdx -= 1;
      if iInput = INPUT_MSCRDOWN then iIdx := (iIdx + 1) mod iArray.Size;
    until iInput in [0,INPUT_ESCAPE,INPUT_OK,INPUT_MLEFT,INPUT_MRIGHT];
    if iInput in [INPUT_OK,INPUT_MLEFT] then
    begin
      if iArray[ iIdx ] = Slot[ efWeapon2 ] then
      begin
        DoScrollSwap.Command := COMMAND_SWAPWEAPON
      end
      else
      if iArray[ iIdx ] <> Slot[ efWeapon ] then
      begin
        DoScrollSwap.Command := COMMAND_WEAR;
        DoScrollSwap.Item    := iArray[ iIdx ];
      end;
    end;
  end;
  IO.SetHint('');
  FreeAndNil( iArray );
end;

function TInventory.AddAmmo( aAmmoID : DWord; aCount : Word ) : Word;
var iAmount   : Word;
    iAmmoItem : TItem;
    iAmmoMax  : Word;
begin
  iAmmoMax  := LuaSystem.Get(['items',aAmmoID,'ammomax']);
  iAmmoItem := SeekAmmo(aAmmoID);

  if FOwner.Flags[ BF_BACKPACK ] then iAmmoMax := Round(iAmmoMax * 1.4);

  if iAmmoItem <> nil then
  begin
    iAmount := Min(aCount,iAmmoMax-iAmmoItem.Ammo);
    aCount -= iAmount;
    iAmmoItem.Ammo := iAmmoItem.Ammo + iAmount;
  end;
  if aCount = 0 then Exit(0);

  repeat
    if isFull then Exit(aCount);

    iAmount := Min(aCount,iAmmoMax);
    iAmmoItem := TItem.Create(aAmmoID);
    iAmmoItem.Ammo := iAmount;
    Add(iAmmoItem);
    aCount -= iAmount;
  until aCount = 0;
  Exit(0);
end;

function TInventory.isFull: boolean;
var iSize : Integer;
begin
  iSize := Size;
  if FOwner = Player then Exit( iSize >= Player.InventorySize );
  Exit(iSize >= High(TItemSlot));
end;


procedure TInventory.EqSwap(aSlot1, aSlot2: TEqSlot);
var iItem : TItem;
begin
  iItem          := FSlots[aSlot1];
  FSlots[aSlot1] := FSlots[aSlot2];
  FSlots[aSlot2] := iItem;
end;

procedure TInventory.EqTick;
var iSlot : TEqSlot;
begin
  for iSlot in TEqSlot do
    if FSlots[iSlot] <> nil then
      FSlots[iSlot].Tick(FOwner);
end;

procedure TInventory.ClearSlot ( aItem : TItem ) ;
var iSlot : TEqSlot;
begin
  for iSlot in TEqSlot do
    if FSlots[iSlot] = aItem then
      setSlot( iSlot, nil );
end;

function TInventory.DoWear ( aItem : TItem ) : Boolean;
var iItem : TItem;
begin
  if aItem = nil then Exit( False );
  if aItem.Hooks[ Hook_OnEquipCheck ] then
    if not aItem.CallHookCheck( Hook_OnEquipCheck,[FOwner] ) then Exit( False );
  iItem := FSlots[aItem.eqSlot];
  if (iItem <> nil) and iItem.Flags[ IF_CURSED ] then begin IO.Msg('You can''t, your '+iItem.Name+' is cursed!'); Exit( False ); end;
  IO.Msg('You wear/wield : '+aItem.GetName(false));
  Wear( aItem );
  Exit( True );
end;

function TInventory.DoWear ( aItem : TItem; aSlot : TEqSlot ) : Boolean;
var iItem : TItem;
begin
  if aItem = nil then Exit( False );
  if aItem.Hooks[ Hook_OnEquipCheck ] then
    if not aItem.CallHookCheck( Hook_OnEquipCheck,[FOwner] ) then Exit( False );
  iItem := FSlots[aSlot];
  if (iItem <> nil) and iItem.Flags[ IF_CURSED ] then begin IO.Msg('You can''t, your '+iItem.Name+' is cursed!'); Exit( False ); end;
  IO.Msg('You wear/wield : '+aItem.GetName(false));
  setSlot( aSlot, aItem );
  Exit( True );
end;

function TInventory.Contains( aItem : TItem ) : Boolean;
begin
  Exit( aItem.Parent = FOwner );
end;

function TInventory.FindSlot ( aItem : TItem ) : TEqSlot;
var iSlot : TEqSlot;
begin
  for iSlot in TEqSlot do
    if FSlots[iSlot] = aItem then Exit( iSlot );
  Exit( TEqSlot(0) );
end;

function TInventory.GetEnumerator : TInventoryEnumerator;
begin
  GetEnumerator.Create(FOwner);
end;

function TInventory.Equipped ( aItem : TItem ) : Boolean;
var iSlot : TEqSlot;
begin
  for iSlot in TEqSlot do
    if FSlots[ iSlot ] = aItem then
      Exit( True );
  Exit( False );
end;

end.

