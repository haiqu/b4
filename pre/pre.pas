{ -----------------------------------------------------------------

  pre : a pattern recognition engine

  copyright (c) 2012 michal j wallace
  see ../LICENSE.org for ( MIT-style ) licensing details

---------------------------------------------------------------- }
{$i xpc.inc }
unit pre;
interface uses xpc;

  type
    Source = interface
      function  ch : Char;
      procedure next;
      procedure mark; // push cursor position to stack
      procedure back; // pop cursor position and return
      procedure free; // pop cursor position but do not return
      procedure keep; // drop, but also generate a token
    end;
    CharSet = set of Char;
    pMatcher = ^Matcher;
    Pattern = class
      function match( pm : pMatcher ) : boolean; virtual; abstract;
    end;
    patterns = array of pattern;


    { matcher contains the hand-written methods that
      actually carry out the work of matching things.

      this class definition also serves as the input
      to pre_gen.py, which generates a bunch of helper
      classes and functions }

    matcher = class
      src  : Source;
      constructor create( var src_in : Source );

      { primitive : character classes }
      function nul : boolean;
      function lit( const c  : char ) : boolean;
      function any( const cs : charset ) : boolean;

      { regular expressions }
      function opt( const p : pattern ) : boolean;   // like regexp '?'
      function rep( const p : pattern ) : boolean;   // like '*'
      function alt( const ps : patterns ) : boolean; // like "|"
      function seq( const ps : patterns ) : boolean; // like "(...)"

      { recursion support }
      function def( const iden : string; const p : pattern ) : boolean;
      function sub( const iden : string ) : boolean;
    end;

  { support for multiple grammars }
  procedure new_grammar( const iden : string );
  procedure end_grammar;
  procedure use_grammar( const iden : string );


implementation

  {$i pre_gen.pas } // generated by pre_gen.py when you run make

  type defarray = array of DefPattern;
  var defs : defarray;

  { support for multiple grammars }
  procedure new_grammar( const iden : string ); begin end;
  procedure end_grammar; begin end;
  procedure use_grammar( const iden : string ); begin end;

  constructor matcher.create( var src_in : Source );
  begin
    self.src := src;
  end;


  { these hand-written routines are used by the objects
    generated in pre_gen.pas }

  { nul always matches, without consuming any characters }
  function matcher.nul : boolean;
  begin
    result := true;
  end;

  { lit tests equality with a specific character }
  function matcher.lit( const c : char ) : boolean;
  begin
    result := src.ch = c ;
  end;

  { any tests membership in a set of characters }
  function matcher.any( const cs : charset ) : boolean;
  begin
    result := src.ch in cs;
  end;

  { alt can match any one of the given patterns }
  // !! NOTE: in this implementation, the first match wins, so it acts
  //    like a parsing expression grammar. Most of the languages I'm
  //    parsing are LL(1), so I don't think this actually makes any
  //    difference.
  function matcher.alt( const ps : patterns ) : boolean;
    var i : integer = 0 ; found : boolean = false;
  begin
    src.mark;
    while not found and ( i < high( ps )) do begin
      found := ps[ i ].match( @self );
      if not found then src.back;
      inc( i )
    end;
    result := found;
  end;


  { opt ( optional ) tries to match a pattern,
    but if the pattern doesn't match, it backtracks
    and returns true anyway.
    algebraically, opt p = alt ( p , nul ) }
  function matcher.opt( const p : pattern ) : boolean;
  begin
    src.mark;
    if p.match( @self ) then src.keep else src.back;
    result := true;
  end;

  { rep ( repeating ) is like opt, but it will keep consuming
    input until the underlying pattern fails. since matching 0
    copies is still a match, rep always succeeds }
  function matcher.rep( const p : pattern ) : boolean;
  begin
    repeat
      src.mark;
      result := p.match( @self );
      if result then src.keep else src.back;
    until not result;
    result := true;
  end;

  { seq ( sequence ) simply matches each pattern from left to right.
    it succeeds if and only if each pattern in the sequence succeeds. }
  function matcher.seq( const ps : patterns ) : boolean;
    var i : integer = 0;
  begin
    result := true;
    while result and ( i < length( ps )) do
    begin
      result := result and ps[ i ].match( @self );
      inc( i )
    end
  end;

  { dictionary routines }

  { def assigns a name to the specified pattern.
    the only reason this is a function rather than a procedure is to
    avoid special cases in the code generator }
  function matcher.def( const iden : string ; const p : pattern ) : boolean;
    var len : integer;
  begin
    len := length( defs );
    setlength( defs, len + 1 );
    defs[ len ].iden := iden;
    defs[ len ].p := p;
    result := true;
  end;

  { lookup searches through the dictionary backward, so that the last
    entry added is the one returned }
  function lookup( const iden : string; var p : pattern ) : boolean;
    var i : integer; found : boolean = false;
  begin
    i := length( defs ) - 1;
    while ( i > -1 ) and not found do begin
      found := defs[ i ].iden = iden;
      if found then p := defs[ i ];
      dec( i )
    end;
    result := found;
  end;

  { sub invokes a rule ( provided it's found in the dictionary ) }
  function matcher.sub( const iden : string ) : boolean;
    var p : pattern;
  begin
    if lookup( iden, p ) then result := p.match( @self )
    else begin writeln( 'couldn''t find sub: ', iden ); halt end
  end;


  { initialization : seed the engine with a simple ebnf parser }

  // this is sort of a workaround for the objfpc syntax
  //
  // given the grammar rule:
  //
  //    expr = term  { "|" term } .
  //
  //  I want to say:
  //
  //    def( 'expr', seq([ sub( 'term' ), rep([ lit( '|' ), sub( 'term' )])]));
  //
  // unfortunately, as far as i can tell, there's no way to express a
  // literal dynamic array like this. ( if there is, i'd love to hear
  // hear about it )
  //
  // in the meantime, i made this little stack machine instead.
  // it's only purpose is to make the ebnf grammar below easier to read.

  var pats : ^patterns; n : integer;

  function  ps : patterns; { creates a new patterns array }
  begin
    n := 0; new( pats ); result := pats^
  end;

  procedure p( pat : pattern ); { appends to the last array }
  begin
    inc( n ); setlength( pats^, n ); pats^[ n ] := pat;
  end;


initialization
  { hand-built bootstrap parser for ebnf grammars
    This uses the simplified pattern constructors
    from the generated include file. }

  new_grammar( 'ebnf' );

  // syntax = { rule } .
  def( 'syntax', rep( sub( 'rule' )));

  // rule = iden "=" expr .
  def( 'rule', seq( ps ));
    p( sub( 'iden' ));
    p( lit( '=' ));
    p( sub( 'expr' ));
    p( lit( '.' ));

  // iden = alpha { alpha | digit } .
  def( 'iden', seq( ps ));
    p( sub( 'alpha' ));
    p( sub( 'iden-tail' ));
  def( 'iden-tail', rep( alt( ps )));
    p( sub( 'alpha' ));
    p( sub( 'digit' ));

  // alpha = 'a' | ... | 'z' | 'A' | ... | 'Z'
  def( 'alpha',   any([ 'a'..'z', 'A'..'Z' ]));

  // digit = '0' | ... | '9'
  def( 'digit',   any([ '0'..'9' ]));


  // expr = term  { "|" term } .
  // !! this one has a rep inside a seq. i broke it into two parts
  //    rather than complicate the builder framework further
  def( 'expr', seq( ps ));
    p( sub( 'term' ));
    p( sub( 'expr-tail' ));
  def( 'expr-tail', rep( seq( ps )));
    p( lit( '|' ));
    p( sub( 'term' ));

  // term = { factor }
  def( 'term', rep( sub( 'factor' )));

  // rep = "{" expr "}" .
  def( '{rep}', seq( ps ));
    p( lit( '(' ));
    p( sub( 'expr' ));
    p( lit( ')' ));

  // opt = "[" expr "]" .
  def( '[opt]', seq( ps ));
    p( lit( '[' ));
    p( sub( 'expr' ));
    p( lit( ']' ));

  // grp = "(" expr ")" .
  def( '(grp)', seq( ps ));
    p( lit( '(' ));
    p( sub( 'expr' ));
    p( lit( ')' ));


  // factor = iden | string | rep | opt | grp .
  def( 'factor', alt( ps ));
    p( sub( 'iden' ));
    p( sub( 'string' ));
    p( sub( '{rep}' ));
    p( sub( '[opt]' ));
    p( sub( '(grp)' ));

  // str = """ { str-esc | any other character } """
  def( 'str', seq( ps ));
    p( lit( '"' ));
    p( sub( 'str-esc' ));
    p( lit( '"' ));

  // esc = "" ( "" | """ )
  //
  // Note : I use the ascii escape character as an escape character.
  // That is its purpose. :)
  //
  // If you can't see it in the line above, please consider filing
  // a bug report with whoever makes the tool you're using.
  def( 'str-esc', alt( ps ));
    p( sub( 'escaped' ));
    p( any([ #0 .. #255 ] - [ '"', #27 ])); // here, "-" means 'excluding'
  def( 'escaped', seq( ps ));
    p( lit( #27 ));
    p( any([ #0 .. #255 ]));

  end_grammar;
end.
