// ~NRCOL
Unit PWVCL;

Interface
Uses
  WebApplication,
  WebTemplate,
  XMLBase,
  PWMain,
  Sysutils,
  Classes;

Type
  // This class groups any number of input elements
  TWebEditDialog = Class(TWebComponent)
  Private
    fOnSubmit : TWebEvent;
    fOnCancel : TWebEvent;
    Procedure DialogSubmitAsButton(Caller : TXMLTag);
    Procedure DialogCancelAsButton(Caller : TXMLTag);
    Procedure DialogCarryOnVar(Caller : TXMLTag);
    Procedure DialogForm(Caller : TXMLTag);
    Procedure DialogSubmitAct(Actions : TTokenList; Depth : LongWord);
    Procedure DialogCancelAct(Actions : TTokenList; Depth : LongWord);
  Public
    Constructor Create(Name, Tmpl : String; Owner : TWebComponent);
    Property OnSubmit : TWebEvent Read fOnSubmit Write fOnSubmit;
    Property OnCancel : TWebEvent Read fOnCancel Write fOnCancel;
  End;

Implementation

Procedure TWebEditDialog.DialogSubmitAsButton(Caller : TXMLTag);
Begin
  WebWrite('<button type="submit" name="action" value="' + ActionName('submit') + '">');
  Caller.EmitChilds;
  WebWrite('</button>');
End;

Procedure TWebEditDialog.DialogCancelAsButton(Caller : TXMLTag);
Begin
  WebWrite('<button type="submit" name="action" value="' + ActionName('cancel') + '">');
  Caller.EmitChilds;
  WebWrite('</button>');
End;

Procedure TWebEditDialog.DialogCarryOnVar(Caller : TXMLTag);
Begin
  WebWrite('<input type="hidden" ' + Caller.Attributes.DelimitedText +
    ' value="' + GetCGIVar(
    UnQuote(Caller.Attributes.Values['name'])
    ) + '"/>');
End;

Procedure TWebEditDialog.DialogForm(Caller : TXMLTag);
Var
  ActAttrib : LongInt;
Begin
  ActAttrib := Caller.Attributes.IndexOfName('action');
  If ActAttrib > -1 Then
    Caller.Attributes.Delete(ActAttrib);
  Caller.Attributes.Add('action="' + SelfReference + '"');
  WebWrite('<form ' + Caller.Attributes.DelimitedText + '>');
  Caller.EmitChilds;
  WebWrite('</form>');
End;

Procedure TWebEditDialog.DialogSubmitAct(Actions : TTokenList; Depth : LongWord);
Begin
  If Assigned(fOnSubmit) Then
    fOnSubmit();
End;

Procedure TWebEditDialog.DialogCancelAct(Actions : TTokenList; Depth : LongWord);
Begin
  If Assigned(fOnCancel) Then
    fOnCancel();
End;

Constructor TWebEditDialog.Create(Name, Tmpl : String; Owner : TWebComponent);
Begin
  Inherited Create(Name, Tmpl, Owner);
  Template.Tag['dialog'] := Self.DialogForm;
  Template.Tag['submit'] := Self.DialogSubmitAsButton;
  Template.Tag['cancel'] := Self.DialogCancelAsButton;
  Template.Tag['carry']  := Self.DialogCarryOnVar;
  Actions['submit']      := Self.DialogSubmitAct;
  Actions['cancel']      := Self.DialogCancelAct;
End;

End.