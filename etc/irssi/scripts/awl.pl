use strict; 
use Irssi (); 
use Irssi::TextUI;
use vars qw($VERSION %IRSSI);
$VERSION = '0.6ca';
%IRSSI = (
  original_authors => q(BC-bd,        Veli,          Timo Sirainen, ).
                      q(Wouter Coekaerts,    Jean-Yves Lefort), 
  original_contact => q(bd@bc-bd.org, veli@piipiip.net, tss@iki.fi, ).
                      q(wouter@coekaerts.be, jylefort@brutele.be),
  authors          => q(Nei),
  contact          => q(Nei@QuakeNet),
  url              =>  "http://anti.teamidiot.de/",
  name             => q(awl),
  description      => q(Adds a permanent advanced window list on the right or ).
                      q(in a statusbar.),
  description2     => q(Based on chanact.pl which was apparently based on ).
                      q(lightbar.c and nicklist.pl with various other ideas ).
                      q(from random scripts.),
  license          => q(GNU GPLv2 or later),
);
my $replaces = '[=]'; 
my $actString = [];   
my $currentLines = 0;
my $resetNeeded;      
my $needRemake;       
sub GLOB_QUEUE_TIMER () { 100 }
my $globTime = undef; 
my $SCREEN_MODE;
my $DISABLE_SCREEN_TEMP;
my $currentColumns = 0;
my $screenResizing;
my ($screenHeight, $screenWidth);
my $screenansi = bless {
  NAME => 'Screen::ANSI',
  PARENTS => [],
  METHODS => {
    dcs   => sub { "\033P" },
    st    => sub { "\033\\"},
  }
}, 'Class::Classless::X';
my $terminfo = bless { 
  NAME => 'Term::Info::xterm',
  PARENTS => [],
  METHODS => {
    civis => sub { "\033[?25l" },
    sc    => sub { "\0337" },
    cup   => sub { shift;shift; "\033[" . ($_[0] + 1) . ';' . ($_[1] + 1) . 'H' },
    el    => sub { "\033[K" },
    rc    => sub { "\0338" },
    cnorm => sub { "\033[?25h" },
    setab => sub { shift;shift; "\033[4" . $_[0] . 'm' },
    setaf => sub { shift;shift; "\033[3" . $_[0] . 'm' },
    bold  => sub { "\033[1m" },
    blink => sub { "\033[5m" },
    rev   => sub { "\033[7m" },
    op    => sub { "\033[39;49m" },
  }
}, 'Class::Classless::X';
sub setc () {
  $IRSSI{'name'}
}
sub set ($) {
  setc . '_' . shift
}
my %statusbars;       
sub add_statusbar {
  for (@_) {
    for my $l ($_) { {
      no strict 'refs'; 
      *{set$l} = sub { awl($l, @_) };
    }; }
    Irssi::command('statusbar ' . (set$_) . ' reset');
    Irssi::command('statusbar ' . (set$_) . ' enable');
    if (lc Irssi::settings_get_str(set 'placement') eq 'top') {
      Irssi::command('statusbar ' . (set$_) . ' placement top');
    }
    if ((my $x = int Irssi::settings_get_int(set 'position')) != 0) {
      Irssi::command('statusbar ' . (set$_) . ' position ' . $x);
    }
    Irssi::command('statusbar ' . (set$_) . ' add -priority 100 -alignment left barstart');
    Irssi::command('statusbar ' . (set$_) . ' add ' . (set$_));
    Irssi::command('statusbar ' . (set$_) . ' add -priority 100 -alignment right barend');
    Irssi::command('statusbar ' . (set$_) . ' disable');
    Irssi::statusbar_item_register(set$_, '$0', set$_);
    $statusbars{$_} = {};
  }
}
sub remove_statusbar {
  for (@_) {
    Irssi::command('statusbar ' . (set$_) . ' reset');
    Irssi::statusbar_item_unregister(set$_); 
    for my $l ($_) { {
      no strict 'refs';
      undef &{set$l};
    }; }
    delete $statusbars{$_};
  }
}
sub syncLines {
  my $temp = $currentLines;
  $currentLines = @$actString;
  #Irssi::print("current lines: $temp new lines: $currentLines");
  my $currMaxLines = Irssi::settings_get_int(set 'maxlines');
  if ($currMaxLines > 0 and @$actString > $currMaxLines) {
    $currentLines = $currMaxLines;
  }
  elsif ($currMaxLines < 0) {
    $currentLines = abs($currMaxLines);
  }
  return if ($temp == $currentLines);
  if ($currentLines > $temp) {
    for ($temp .. ($currentLines - 1)) {
      add_statusbar($_);
      Irssi::command('statusbar ' . (set$_) . ' enable');
    }
  }
  else {
    for ($_ = ($temp - 1); $_ >= $currentLines; $_--) {
      Irssi::command('statusbar ' . (set$_) . ' disable');
      remove_statusbar($_);
    }
  }
}
sub awl {
  my ($line, $item, $get_size_only) = @_;
  if ($needRemake) {
    $needRemake = undef;
    remake();
  }
  my $text = $actString->[$line];  
  $text = '' unless defined $text; 
  $item->default_handler($get_size_only, $text, '', 1);
}
my %killBar;
sub get_old_status {
  my ($textDest, $cont, $cont_stripped) = @_;
  if ($textDest->{'level'} == 524288 and $textDest->{'target'} eq ''
      and !defined($textDest->{'server'})
  ) {
    my $name = quotemeta(set '');
    if ($cont_stripped =~ m/^$name(\d+)\s/) { $killBar{$1} = {}; }
    Irssi::signal_stop();
  }
}
sub killOldStatus {
  %killBar = ();
  Irssi::signal_add_first('print text' => 'get_old_status');
  Irssi::command('statusbar');
  Irssi::signal_remove('print text' => 'get_old_status');
  remove_statusbar(keys %killBar);
}
my %keymap;
sub get_keymap {
  my ($textDest, undef, $cont_stripped) = @_;
  if ($textDest->{'level'} == 524288 and $textDest->{'target'} eq ''
      and !defined($textDest->{'server'})
  ) {
    if ($cont_stripped =~ m/((?:meta-)+)(.)\s+change_window (\d+)/) {
      my ($level, $key, $window) = ($1, $2, $3);
      my $numlevel = ($level =~ y/-//) - 1;
      $keymap{$window} = ('-' x $numlevel) . "$key";
    }
    Irssi::signal_stop();
  }
}
sub update_keymap {
  %keymap = ();
  Irssi::signal_remove('command bind' => 'watch_keymap');
  Irssi::signal_add_first('print text' => 'get_keymap');
  Irssi::command('bind'); 
  Irssi::signal_remove('print text' => 'get_keymap');
  Irssi::signal_add('command bind' => 'watch_keymap');
  Irssi::timeout_add_once(100, 'eventChanged', undef);
}
sub watch_keymap {
  Irssi::timeout_add_once(1000, 'update_keymap', undef);
}
update_keymap();
sub expand {
  my ($string, %format) = @_;
  my ($exp, $repl);
  $string =~ s/\$$exp/$repl/g while (($exp, $repl) = each(%format));
  return $string;
}
my %strip_table = (
  (map { $_ => '' } (split //, '04261537' .  'kbgcrmyw' . 'KBGCRMYW' . 'U9_8:|FnN>#[')),
  (map { $_ => $_ } (split //, '{}%')),
);
sub ir_strip_codes { 
  my $o = shift;
  $o =~ s/(%(.))/exists $strip_table{$2} ? $strip_table{$2} : $1/gex;
  $o
}
sub ir_parse_special {
  my $o; my $i = shift;
  #if ($_[0]) { 
  #  eval {
  #    $o = $_[0]->parse_special($i);
  #  };
  #  unless ($@) {
  #    return $o;
  #  }
  #}
  my $win = shift || Irssi::active_win();
  my $server = Irssi::active_server();
  if (ref $win and ref $win->{'active'}) {
    $o = $win->{'active'}->parse_special($i);
  }
  elsif (ref $win and ref $win->{'active_server'}) {
    $o = $win->{'active_server'}->parse_special($i);
  }
  elsif (ref $server) {
    $o =  $server->parse_special($i);
  }
  else {
    $o = Irssi::parse_special($i);
  }
  $o
}
sub ir_parse_special_protected {
  my $o; my $i = shift;
  $i =~ s/
    ( \\. ) | 
    ( \$[^% $\]+ ) 
  /
    if ($1) { $1 }
    elsif ($2) { my $i2 = $2; ir_fe(ir_parse_special($i2, @_)) }
    else { $& }
  /gex;
  $i
}
sub sb_ctfe { 
  Irssi::current_theme->format_expand(
    shift,
    (
      Irssi::EXPAND_FLAG_IGNORE_REPLACES
        |
      ($_[0]?0:Irssi::EXPAND_FLAG_IGNORE_EMPTY)
    )
  )
}
sub sb_expand { 
  ir_parse_special(
    sb_ctfe(shift)
  )
}
sub sb_strip {
  ir_strip_codes(
    sb_expand(shift)
  ); 
}
sub sb_length {
  my $term_type = 'term_type';
  if (Irssi::version > 20040819) { 
    $term_type = 'term_charset';
  }
  #if (lc Irssi::settings_get_str($term_type) eq '8bit'
  #    or Irssi::settings_get_str($term_type) =~ /^iso/i
  #) {
  #  length(sb_strip(shift))
  #}
  #else {
  my $temp = sb_strip(shift);
  my $length;
  eval {
    require Text::CharWidth;
    $length = Text::CharWidth::mbswidth($temp);
  };
  unless ($@) {
    return $length;
  }
  else {
    if (lc Irssi::settings_get_str($term_type) eq 'utf-8') {
      eval {
        no warnings;
        require Encode;
        #$temp = Encode::decode_utf8($temp); 
        Encode::_utf8_on($temp);
      };
    }
    length($temp)
  }
  #}
}
sub ir_escape {
  my $min_level = $_[1] || 0; my $level = $min_level;
  my $o = shift;
  $o =~ s/
    (  %.  )  | 
    (  \{  )  | 
    (  \}  )  | 
    (  \\  )  | 
    (  \$(?=[^\\])  )  | 
    (  \$  ) 
  /
    if ($1) { $1 } 
    elsif ($2) { $level++; $2 } 
    elsif ($3) { if ($level > $min_level) { $level--; } $3 } 
    elsif ($4) { '\\'x(2**$level) } 
    elsif ($5) { '\\'x(2**$level-1) . '$' . '\\'x(2**$level-1) } 
    else { '\\'x(2**$level-1) . '$' } 
  /gex;
  $o
}
sub ir_fe { 
  my $x = shift;
  $x =~ s/([%{}])/%$1/g;
  #$x =~ s/(\\|\$|[ ])/\\$1/g; 
  $x =~ s/(\\|\$)/\\$1/g;
  #$x =~ s/(\$(?=.))|(\$)/$1?"\\\$\\":"\\\$"/ge; 
  #$x =~ s/\\/\\\\/g; 
  $x
}
sub ir_ve { 
  my $x = shift;
  #$x =~ s/([%{}])/%$1/g;
  $x =~ s/(\\|\$|[ ])/\\$1/g;
  $x
}
my %ansi_table;
{
  my ($i, $j, $k) = (0, 0, 0);
  %ansi_table = (
    (map { $_ => $terminfo->setab($i++) } (split //, '01234567' )),
    (map { $_ => $terminfo->setaf($j++) } (split //, 'krgybmcw' )),
    (map { $_ => $terminfo->bold() .
                 $terminfo->setaf($k++) } (split //, 'KRGYBMCW')),
    #(map { $_ => $terminfo->op() } (split //, 'nN')),
    (map { $_ => $terminfo->op() } (split //, 'n')),
    (map { $_ => "\033[0m" } (split //, 'N')), 
    F => $terminfo->blink(),
    8 => $terminfo->rev(),
    (map { $_ => $terminfo->bold() } (split //, '9_')),
    (map { $_ => '' } (split //, ':|>#[')),
    (map { $_ => $_ } (split //, '{}%')),
  )
}
sub formats_to_ansi_basic {
  my $o = shift;
  $o =~ s/(%(.))/exists $ansi_table{$2} ? $ansi_table{$2} : $1/gex;
  $o
}
sub lc1459 ($) { my $x = shift; $x =~ y/A-Z][\^/a-z}{|~/; $x }
Irssi::settings_add_str(setc, 'banned_channels', '');
Irssi::settings_add_bool(setc, 'banned_channels_on', 0);
my %banned_channels = map { lc1459($_) => undef }
split ' ', Irssi::settings_get_str('banned_channels');
Irssi::settings_add_str(setc, 'fancy_abbrev', 'fancy');
sub remake () {
  #$callcount++;
  #my $xx = $callcount; Irssi::print("starting remake [ $xx ]");
  my ($hilight, $number, $display);
  my $separator = '{sb_act_sep ' . Irssi::settings_get_str(set 'separator') .
    '}';
  my $custSort = Irssi::settings_get_str(set 'sort');
  my $custSortDir = 1;
  if ($custSort =~ /^[-!](.*)/) {
    $custSortDir = -1;
    $custSort = $1;
  }
  my @wins = 
    sort {
      (
        ( (int($a->{$custSort}) <=> int($b->{$custSort})) * $custSortDir )
          ||
        ($a->{'refnum'} <=> $b->{'refnum'})
      )
    } Irssi::windows;
  my $block = Irssi::settings_get_int(set 'block');
  my $columns = $currentColumns;
  my $oldActString = $actString if $SCREEN_MODE;
  $actString = $SCREEN_MODE ? ['   A W L'] : [];
  my $line = $SCREEN_MODE ? 1 : 0;
  my $width = $SCREEN_MODE
      ?
    $screenWidth - abs($block)*$columns + 1
      :
    ([Irssi::windows]->[0]{'width'} - sb_length('{sb x}'));
  my $height = $screenHeight - abs(Irssi::settings_get_int(set
      'height_adjust'));
  my ($numPad, $keyPad) = (0, 0);
  my %abbrevList;
  if ($SCREEN_MODE or Irssi::settings_get_bool(set 'sbar_maxlength')
      or ($block < 0)
  ) {
    %abbrevList = ();
    if (Irssi::settings_get_str('fancy_abbrev') !~ /^(no|off|head)/i) {
      my @nameList = map { ref $_ ? $_->get_active_name : '' } @wins;
      for (my $i = 0; $i < @nameList - 1; ++$i) {
        my ($x, $y) = ($nameList[$i], $nameList[$i + 1]);
        for ($x, $y) { s/^[+#!=]// }
        my $res = Algorithm::LCSS::LCSS($x, $y);
        if (defined $res) {
          #Irssi::print("common pattern $x $y : $res");
          #Irssi::print("found at $nameList[$i] ".index($nameList[$i],
          #    $res));
          $abbrevList{$nameList[$i]} = int (index($nameList[$i], $res) +
            (length($res) / 2));
          #Irssi::print("found at ".$nameList[$i+1]." ".index($nameList[$i+1],
          #    $res));
          $abbrevList{$nameList[$i+1]} = int (index($nameList[$i+1], $res) +
            (length($res) / 2));
        }
      }
    }
    if ($SCREEN_MODE or ($block < 0)) {
      $numPad = length((sort { length($b) <=> length($a) } keys %keymap)[0]);
      $keyPad = length((sort { length($b) <=> length($a) } values %keymap)[0]);
    }
  }
  if ($SCREEN_MODE) {
    print STDERR $screenansi->dcs().
                 $terminfo->civis().
             $terminfo->sc().
             $screenansi->st();
    if (@$oldActString < 1) {
      print STDERR $screenansi->dcs().
               $terminfo->cup(0, $width).
                   $actString->[0].
               $terminfo->el().
                   $screenansi->st();
    }
  }
  foreach my $win (@wins) {
    unless ($SCREEN_MODE) {
      $actString->[$line] = '' unless defined $actString->[$line]
          or Irssi::settings_get_bool(set 'all_disable');
    }
    !ref($win) && next;
    my $name = $win->get_active_name;
    $name = '*' if (Irssi::settings_get_bool('banned_channels_on') and exists
      $banned_channels{lc1459($name)});
    $name = $win->{'name'} if $name ne '*' and $win->{'name'} ne ''
      and Irssi::settings_get_bool(set 'prefer_name');
    my $active = $win->{'active'};
    my $colour = $win->{'hilight_color'};
    if (!defined $colour) { $colour = ''; }
    if ($win->{'data_level'} < Irssi::settings_get_int(set 'hide_data')) {
      next; } 
    if    ($win->{'data_level'} == 0) { $hilight = '{sb_act_none '; }
    elsif ($win->{'data_level'} == 1) { $hilight = '{sb_act_text '; }
    elsif ($win->{'data_level'} == 2) { $hilight = '{sb_act_msg '; }
    elsif ($colour             ne '') { $hilight = "{sb_act_hilight_color $colour "; }
    elsif ($win->{'data_level'} == 3) { $hilight = '{sb_act_hilight '; }
    else                              { $hilight = '{sb_act_special '; }
    $number = $win->{'refnum'};
    my @display = ('display_nokey');
    if (defined $keymap{$number} and $keymap{$number} ne '') {
      unshift @display, map { (my $cpy = $_) =~ s/_no/_/; $cpy } @display;
    }
    if (Irssi::active_win->{'refnum'} == $number) {
      unshift @display, map { my $cpy = $_; $cpy .= '_active'; $cpy } @display;
    }
    #Irssi::print("win $number [@display]: " . join '.', split //, join '<<', map {
      #    Irssi::settings_get_str(set $_) } @display);
    $display = (grep { $_ }
      map { Irssi::settings_get_str(set $_) }
      @display)[0];
      #Irssi::print("win $number : " . join '.', split //, $display);
    if ($SCREEN_MODE or Irssi::settings_get_bool(set 'sbar_maxlength')
        or ($block < 0)
    ) {
      my $baseLength = sb_length(ir_escape(ir_ve(ir_parse_special_protected(sb_ctfe(
        '{sb_background}' . expand($display,
        C => ir_fe('x'),
        N => $number . (' 'x($numPad - length($number))),
        Q => ir_fe((' 'x($keyPad - length($keymap{$number}))) . $keymap{$number}),
        H => $hilight,
        S => '}{sb_background}'
      ), 1), $win)))) - 1;
      my $diff = abs($block) - (length($name) + $baseLength);
      if ($diff < 0) { 
        if (abs($diff) >= length($name)) { $name = '' } 
        elsif (abs($diff) + 1 >= length($name)) { $name = substr($name,
            0, 1); }
        else {
          my $middle = exists $abbrevList{$name} ?
          (($abbrevList{$name} + (2*(length($name) / 2)))/3) :
            ((Irssi::settings_get_str('fancy_abbrev') =~ /^head/i) ?
                length($name) :
            (length($name) / 2));
          my $cut = int($middle - (abs($diff) / 2) + .55); 
          $cut = 1 if $cut < 1;
          $cut = length($name) - abs($diff) - 1 if $cut > (length($name) -
            abs($diff) - 1);
          $name = substr($name, 0, $cut) . '~' . substr($name, $cut +
            abs($diff) + 1);
        }
      }
      elsif ($SCREEN_MODE or ($block < 0)) {
        $name .= (' ' x $diff);
      }
    }
    my $add = ir_ve(ir_parse_special_protected(sb_ctfe('{sb_background}' . expand($display,
      C => ir_fe($name),
      N => $number . (' 'x($numPad - length($number))),
      Q => ir_fe((' 'x($keyPad - length($keymap{$number}))) . $keymap{$number}),
      H => $hilight,
      S => '}{sb_background}'
    ), 1), $win));
    if ($SCREEN_MODE) {
      $actString->[$line] = $add;
      if ((!defined $oldActString->[$line]
          or $oldActString->[$line] ne $actString->[$line])
          and
        $line <= ($columns * $height)
      ) {
        print STDERR $screenansi->dcs().
                 $terminfo->cup(($line-1) % $height+1, $width + (
                   abs($block) * int(($line-1) / $height))).
        formats_to_ansi_basic(sb_expand(ir_escape($actString->[$line]))).
                #$terminfo->el().
                 $screenansi->st();
      }
      $line++;
    }
    else {
      #$temp =~ s/\{\S+?(?:\s(.*?))?\}/$1/g;
      #$temp =~ s/\\\\\\\\/\\/g; 
      $actString->[$line] = '' unless defined $actString->[$line];
      if (sb_length(ir_escape($actString->[$line] . $add)) >= $width) {
        $actString->[$line] .= ' ' x ($width - sb_length(ir_escape(
          $actString->[$line])));
        $line++;
      }
      $actString->[$line] .= $add . $separator;
      #Irssi::print("line $line: ".$actString->[$line]);
      #Irssi::print("temp $line: ".$temp);
    }
  }
  if ($SCREEN_MODE) {
    while ($line <= ($columns * $height)) {
      print STDERR $screenansi->dcs().
               $terminfo->cup(($line-1) % $height+1, $width + (
                 abs($block) * int(($line-1) / $height))).
               $terminfo->el().
               $screenansi->st();
      $line++;
    }
    print STDERR $screenansi->dcs().
             $terminfo->rc().
                 $terminfo->cnorm().
             $screenansi->st();
  }
  else {
    for (my $p = 0; $p < @$actString; $p++) { 
      my $x = $actString->[$p];              
      $x =~ s/\Q$separator\E([ ]*)$/$1/;
      #Irssi::print("[$p]".'current:'.join'.',split//,sb_strip(ir_escape($x,0)));
      #Irssi::print("assumed length before:".sb_length(ir_escape($x,0)));
      $x = "{sb $x}";
      #Irssi::print("[$p]".'new:'.join'.',split//,sb_expand(ir_escape($x,0)));
      #Irssi::print("[$p]".'new:'.join'.',split//,ir_escape($x,0));
      #Irssi::print("assumed length after:".sb_length(ir_escape($x,0)));
      $x = ir_escape($x);
      #Irssi::print("[$p]".'REALnew:'.join'.',split//,sb_strip($x));
      $actString->[$p] = $x;
    }
  }
  #Irssi::print("remake [ $xx ] finished");
}
sub awlHasChanged () {
  $globTime = undef;
  my $temp = ($SCREEN_MODE ?
    "\\\n" . Irssi::settings_get_int(set 'block').
    Irssi::settings_get_int(set 'height_adjust')
    : "!\n" . Irssi::settings_get_str(set 'placement').
    Irssi::settings_get_int(set 'position')).
    Irssi::settings_get_str(set 'automode');
  if ($temp ne $resetNeeded) { wlreset(); return; }
  #Irssi::print("awl has changed, calls to remake so far: $callcount");
  $needRemake = 1;
  #remake();
  if (
    ($SCREEN_MODE and !$DISABLE_SCREEN_TEMP)
      or
    ($needRemake and Irssi::settings_get_bool(set 'all_disable'))
      or
    (!Irssi::settings_get_bool(set 'all_disable') and $currentLines < 1)
  ) {
    $needRemake = undef;
    remake();
  }
  unless ($SCREEN_MODE) {
    Irssi::timeout_add_once(100, 'syncLines', undef);
    for (keys %statusbars) {
      Irssi::statusbar_items_redraw(set$_);
    }
  }
  else {
    Irssi::timeout_add_once(100, 'syncColumns', undef);
  }
}
sub eventChanged () { 
  if (defined $globTime) {
    Irssi::timeout_remove($globTime);
  } 
  $globTime = Irssi::timeout_add_once(GLOB_QUEUE_TIMER, 'awlHasChanged', undef);
}
sub screenFullRedraw {
  my ($window) = @_;
  if (!ref $window or $window->{'refnum'} == Irssi::active_win->{'refnum'}) {
    $actString = [];
    eventChanged();
  }
}
sub screenSize { 
  $screenResizing = 1;
  system 'screen -x '.$ENV{'STY'}.' -X fit';
  my ($row, $col) = split ' ', `stty size`;
  $screenWidth = $col-1;
  $screenHeight = $row-1;
  Irssi::timeout_add_once(100, sub {
    my ($new_irssi_width) = @_;
    $new_irssi_width -= abs(Irssi::settings_get_int(set
        'block'))*$currentColumns - 1;
    system 'screen -x '.$ENV{'STY'}.' -X width -w ' . $new_irssi_width;
    Irssi::timeout_add_once(10,sub {$screenResizing = 0; screenFullRedraw()}, []);
  }, $screenWidth);
}
sub screenOff {
  my ($unloadMode) = @_;
  Irssi::signal_remove('gui print text finished' => 'screenFullRedraw');
  Irssi::signal_remove('gui page scrolled' => 'screenFullRedraw');
  Irssi::signal_remove('window changed' => 'screenFullRedraw');
  Irssi::signal_remove('window changed automatic' => 'screenFullRedraw');
  if ($unloadMode) {
    Irssi::signal_remove('terminal resized' => 'resizeTerm');
  }
  system 'screen -x '.$ENV{'STY'}.' -X fit';
}
sub syncColumns {
  return if (@$actString == 0);
  my $temp = $currentColumns;
  #Irssi::print("current columns $temp");
  my $height = $screenHeight - abs(Irssi::settings_get_int(set
      'height_adjust'));
  $currentColumns = int(($#$actString-1) / $height) + 1;
  #Irssi::print("objects in actstring:".scalar(@$actString).", screen height:".
  #  $height);
  my $currMaxColumns = Irssi::settings_get_int(set 'columns');
  if ($currMaxColumns > 0 and $currentColumns > $currMaxColumns) {
    $currentColumns = $currMaxColumns;
  }
  elsif ($currMaxColumns < 0) {
    $currentColumns = abs($currMaxColumns);
  }
  return if ($temp == $currentColumns);
  screenSize();
}
sub resizeTerm () {
  if ($SCREEN_MODE and !$screenResizing) {
    $screenResizing = 1;
    Irssi::timeout_add_once(10, 'screenSize', undef);
  }
  Irssi::timeout_add_once(100, 'eventChanged', undef);
}
Irssi::settings_add_str(setc, set 'display_nokey', '[$N]$H$C$S');
Irssi::settings_add_str(setc, set 'display_key', '[$Q=$N]$H$C$S');
Irssi::settings_add_str(setc, set 'display_nokey_active', '');
Irssi::settings_add_str(setc, set 'display_key_active', '');
Irssi::settings_add_str(setc, set 'separator', "\\ ");
Irssi::settings_add_bool(setc, set 'prefer_name', 0);
Irssi::settings_add_int(setc, set 'hide_data', 0);
Irssi::settings_add_int(setc, set 'maxlines', 9);
Irssi::settings_add_int(setc, set 'columns', 1);
Irssi::settings_add_int(setc, set 'block', 20);
Irssi::settings_add_bool(setc, set 'sbar_maxlength', 0);
Irssi::settings_add_int(setc, set 'height_adjust', 2);
Irssi::settings_add_str(setc, set 'sort', 'refnum');
Irssi::settings_add_str(setc, set 'placement', 'bottom');
Irssi::settings_add_int(setc, set 'position', 0);
Irssi::settings_add_bool(setc, set 'all_disable', 0);
Irssi::settings_add_str(setc, set 'automode', 'sbar');
sub wlreset {
  $actString = [];
  $currentLines = 0; 
  #update_keymap();
  killOldStatus();
  #add_statusbar(0);
  #Irssi::command('statusbar wl0 enable');
  my $was_screen_mode = $SCREEN_MODE;
  if ($SCREEN_MODE = (Irssi::settings_get_str(set 'automode') =~ /screen/i)
      and
    !$was_screen_mode
  ) {
    if (!defined $ENV{'STY'}) {
      Irssi::print('Screen mode can only be used in GNU screen but no '.
        'screen was found.', MSGLEVEL_CLIENTERROR);
      $SCREEN_MODE = undef;
    }
    else {
      Irssi::signal_add_last('gui print text finished' => 'screenFullRedraw');
      Irssi::signal_add_last('gui page scrolled' => 'screenFullRedraw');
      Irssi::signal_add('window changed' => 'screenFullRedraw');
      Irssi::signal_add('window changed automatic' => 'screenFullRedraw');
    }
  }
  elsif ($was_screen_mode and !$SCREEN_MODE) {
    screenOff();
  }
  $resetNeeded = ($SCREEN_MODE ?
    "\\\n" . Irssi::settings_get_int(set 'block').
    Irssi::settings_get_int(set 'height_adjust')
    : "!\n" . Irssi::settings_get_str(set 'placement').
    Irssi::settings_get_int(set 'position')).
    Irssi::settings_get_str(set 'automode');
  resizeTerm();
}
wlreset();
my $Unload;
sub unload ($$$) {
  $Unload = 1;
  Irssi::timeout_add_once(10, sub { $Unload = undef; }, undef);
}
Irssi::signal_add_first('gui exit' => sub { $Unload = undef; });
sub UNLOAD {
  if ($Unload) {
    $actString = ['']; 
    killOldStatus();                  
    if ($SCREEN_MODE) {
      screenOff('unload mode');
    }
  }
}
sub addPrintTextHook { 
  return if $_[0]->{'level'} == 262144 and $_[0]->{'target'} eq ''
      and !defined($_[0]->{'server'});
  if (Irssi::settings_get_str(set 'sort') =~ /^[-!]?last_line$/) {
    Irssi::timeout_add_once(100, 'eventChanged', undef);
  }
}
Irssi::signal_add_first(
  'command script unload' => 'unload'
);
Irssi::signal_add_last({
  'setup changed' => 'eventChanged',
  'print text' => 'addPrintTextHook',
  'terminal resized' => 'resizeTerm',
  'setup reread' => 'wlreset',
  'window hilight' => 'eventChanged',
});
Irssi::signal_add({
  'window created' => 'eventChanged',
  'window destroyed' => 'eventChanged',
  'window name changed' => 'eventChanged',
  'window refnum changed' => 'eventChanged',
  'window changed' => 'eventChanged',
  'window changed automatic' => 'eventChanged',
});
sub runsub {
  my ($cmd) = @_;
  sub {
    my ($data, $server, $item) = @_;
    Irssi::command_runsub($cmd, $data, $server, $item);
  };
}
Irssi::command_bind( setc() => runsub(setc()) );
Irssi::command_bind( setc() . ' paste' => runsub(setc() . ' paste') );
Irssi::command_bind(
  setc() . ' paste on' => sub {
    return unless $SCREEN_MODE;
    my $was_disabled = $DISABLE_SCREEN_TEMP;
    $DISABLE_SCREEN_TEMP = 1;
    Irssi::print('Paste mode is now ON, '.uc(setc()).' is temporarily '.
                 'disabled.');
    if (!$was_disabled) {
      $screenResizing = 1;
      screenOff();
    }
  }
);
Irssi::command_bind(
  setc() . ' paste off' => sub {
    return unless $SCREEN_MODE;
    my $was_disabled = $DISABLE_SCREEN_TEMP;
    $DISABLE_SCREEN_TEMP = undef;
    Irssi::print('Paste mode is now OFF, '.uc(setc()).' is enabled.');
    if ($was_disabled) {
      $SCREEN_MODE = undef;
      $screenResizing = 0;
      wlreset();
    }
  }
);
Irssi::command_bind(
  setc() . ' paste toggle' => sub {
    if ($DISABLE_SCREEN_TEMP) {
      Irssi::command(setc() . ' paste off');
    }
    else {
      Irssi::command(setc() . ' paste on');
    }
  }
);
Irssi::command_bind(
  setc() . ' redraw' => sub {
    return unless $SCREEN_MODE;
    screenFullRedraw();
  }
);
{
  package Algorithm::Diff;
  use strict;
  use integer;    
  #
  sub _withPositionsOfInInterval
  {
     my $aCollection = shift;    
     my $start       = shift;
     my $end         = shift;
     my $keyGen      = shift;
     my %d;
     my $index;
     for ( $index = $start ; $index <= $end ; $index++ )
     {
        my $element = $aCollection->[$index];
        my $key = &$keyGen( $element, @_ );
        if ( exists( $d{$key} ) )
        {
          unshift ( @{ $d{$key} }, $index );
        }
        else
        {
          $d{$key} = [$index];
        }
     }
     return wantarray ? %d : \%d;
  }
  sub _replaceNextLargerWith
  {
     my ( $array, $aValue, $high ) = @_;
     $high ||= $#$array;
     if ( $high == -1 || $aValue > $array->[-1] )
     {
        push ( @$array, $aValue );
        return $high + 1;
     }
     my $low = 0;
     my $index;
     my $found;
     while ( $low <= $high )
     {
        $index = ( $high + $low ) / 2;
        $found = $array->[$index];
        if ( $aValue == $found )
        {
          return undef;
        }
        elsif ( $aValue > $found )
        {
          $low = $index + 1;
        }
        else
        {
          $high = $index - 1;
        }
     }
     $array->[$low] = $aValue;    
     return $low;
  }
  sub _longestCommonSubsequence
  {
     my $a        = shift;    
     my $b        = shift;    
     my $counting = shift;    
     my $keyGen   = shift;    
     my $compare;             
     if ( ref($a) eq 'HASH' )
     {                        
        my $tmp = $b;
        $b = $a;
        $a = $tmp;
     }
     if ( !ref($a) || !ref($b) )
     {
        my @callerInfo = caller(1);
        die 'error: must pass array or hash references to ' . $callerInfo[3];
     }
     if ( !defined($keyGen) )    
     {
        $keyGen = sub { $_[0] };
        $compare = sub { my ( $a, $b ) = @_; $a eq $b };
     }
     else
     {
        $compare = sub {
          my $a = shift;
          my $b = shift;
          &$keyGen( $a, @_ ) eq &$keyGen( $b, @_ );
        };
     }
     my ( $aStart, $aFinish, $matchVector ) = ( 0, $#$a, [] );
     my ( $prunedCount, $bMatches ) = ( 0, {} );
     if ( ref($b) eq 'HASH' )    
     {
        $bMatches = $b;
     }
     else
     {
        my ( $bStart, $bFinish ) = ( 0, $#$b );
        while ( $aStart <= $aFinish
          and $bStart <= $bFinish
          and &$compare( $a->[$aStart], $b->[$bStart], @_ ) )
        {
          $matchVector->[ $aStart++ ] = $bStart++;
          $prunedCount++;
        }
        while ( $aStart <= $aFinish
          and $bStart <= $bFinish
          and &$compare( $a->[$aFinish], $b->[$bFinish], @_ ) )
        {
          $matchVector->[ $aFinish-- ] = $bFinish--;
          $prunedCount++;
        }
        $bMatches =
         _withPositionsOfInInterval( $b, $bStart, $bFinish, $keyGen, @_ );
     }
     my $thresh = [];
     my $links  = [];
     my ( $i, $ai, $j, $k );
     for ( $i = $aStart ; $i <= $aFinish ; $i++ )
     {
        $ai = &$keyGen( $a->[$i], @_ );
        if ( exists( $bMatches->{$ai} ) )
        {
          $k = 0;
          for $j ( @{ $bMatches->{$ai} } )
          {
             if ( $k and $thresh->[$k] > $j and $thresh->[ $k - 1 ] < $j )
             {
                $thresh->[$k] = $j;
             }
             else
             {
                $k = _replaceNextLargerWith( $thresh, $j, $k );
             }
             if ( defined($k) )
             {
                $links->[$k] =
                 [ ( $k ? $links->[ $k - 1 ] : undef ), $i, $j ];
             }
          }
        }
     }
     if (@$thresh)
     {
        return $prunedCount + @$thresh if $counting;
        for ( my $link = $links->[$#$thresh] ; $link ; $link = $link->[0] )
        {
          $matchVector->[ $link->[1] ] = $link->[2];
        }
     }
     elsif ($counting)
     {
        return $prunedCount;
     }
     return wantarray ? @$matchVector : $matchVector;
  }
  sub traverse_sequences
  {
     my $a                 = shift;          
     my $b                 = shift;          
     my $callbacks         = shift || {};
     my $keyGen            = shift;
     my $matchCallback     = $callbacks->{'MATCH'} || sub { };
     my $discardACallback  = $callbacks->{'DISCARD_A'} || sub { };
     my $finishedACallback = $callbacks->{'A_FINISHED'};
     my $discardBCallback  = $callbacks->{'DISCARD_B'} || sub { };
     my $finishedBCallback = $callbacks->{'B_FINISHED'};
     my $matchVector = _longestCommonSubsequence( $a, $b, 0, $keyGen, @_ );
     my $lastA = $#$a;
     my $lastB = $#$b;
     my $bi    = 0;
     my $ai;
     for ( $ai = 0 ; $ai <= $#$matchVector ; $ai++ )
     {
        my $bLine = $matchVector->[$ai];
        if ( defined($bLine) )    
        {
          &$discardBCallback( $ai, $bi++, @_ ) while $bi < $bLine;
          &$matchCallback( $ai,    $bi++, @_ );
        }
        else
        {
          &$discardACallback( $ai, $bi, @_ );
        }
     }
     while ( $ai <= $lastA or $bi <= $lastB )
     {
        if ( $ai == $lastA + 1 and $bi <= $lastB )
        {
          if ( defined($finishedACallback) )
          {
             &$finishedACallback( $lastA, @_ );
             $finishedACallback = undef;
          }
          else
          {
             &$discardBCallback( $ai, $bi++, @_ ) while $bi <= $lastB;
          }
        }
        if ( $bi == $lastB + 1 and $ai <= $lastA )
        {
          if ( defined($finishedBCallback) )
          {
             &$finishedBCallback( $lastB, @_ );
             $finishedBCallback = undef;
          }
          else
          {
             &$discardACallback( $ai++, $bi, @_ ) while $ai <= $lastA;
          }
        }
        &$discardACallback( $ai++, $bi, @_ ) if $ai <= $lastA;
        &$discardBCallback( $ai, $bi++, @_ ) if $bi <= $lastB;
     }
     return 1;
  }
  sub traverse_balanced
  {
     my $a                 = shift;              
     my $b                 = shift;              
     my $callbacks         = shift || {};
     my $keyGen            = shift;
     my $matchCallback     = $callbacks->{'MATCH'} || sub { };
     my $discardACallback  = $callbacks->{'DISCARD_A'} || sub { };
     my $discardBCallback  = $callbacks->{'DISCARD_B'} || sub { };
     my $changeCallback    = $callbacks->{'CHANGE'};
     my $matchVector = _longestCommonSubsequence( $a, $b, 0, $keyGen, @_ );
     my $lastA = $#$a;
     my $lastB = $#$b;
     my $bi    = 0;
     my $ai    = 0;
     my $ma    = -1;
     my $mb;
     while (1)
     {
        do {
          $ma++;
        } while(
             $ma <= $#$matchVector
          &&  !defined $matchVector->[$ma]
        );
        last if $ma > $#$matchVector;    
        $mb = $matchVector->[$ma];
        while ( $ai < $ma || $bi < $mb )
        {
          if ( $ai < $ma && $bi < $mb )
          {
             if ( defined $changeCallback )
             {
                &$changeCallback( $ai++, $bi++, @_ );
             }
             else
             {
                &$discardACallback( $ai++, $bi, @_ );
                &$discardBCallback( $ai, $bi++, @_ );
             }
          }
          elsif ( $ai < $ma )
          {
             &$discardACallback( $ai++, $bi, @_ );
          }
          else
          {
             &$discardBCallback( $ai, $bi++, @_ );
          }
        }
        &$matchCallback( $ai++, $bi++, @_ );
     }
     while ( $ai <= $lastA || $bi <= $lastB )
     {
        if ( $ai <= $lastA && $bi <= $lastB )
        {
          if ( defined $changeCallback )
          {
             &$changeCallback( $ai++, $bi++, @_ );
          }
          else
          {
             &$discardACallback( $ai++, $bi, @_ );
             &$discardBCallback( $ai, $bi++, @_ );
          }
        }
        elsif ( $ai <= $lastA )
        {
          &$discardACallback( $ai++, $bi, @_ );
        }
        else
        {
          &$discardBCallback( $ai, $bi++, @_ );
        }
     }
     return 1;
  }
  sub prepare
  {
     my $a       = shift;    
     my $keyGen  = shift;    
     $keyGen = sub { $_[0] } unless defined($keyGen);
     return scalar _withPositionsOfInInterval( $a, 0, $#$a, $keyGen, @_ );
  }
  sub LCS
  {
     my $a = shift;                  
     my $b = shift;                  
     my $matchVector = _longestCommonSubsequence( $a, $b, 0, @_ );
     my @retval;
     my $i;
     for ( $i = 0 ; $i <= $#$matchVector ; $i++ )
     {
        if ( defined( $matchVector->[$i] ) )
        {
          push ( @retval, $a->[$i] );
        }
     }
     return wantarray ? @retval : \@retval;
  }
  sub LCS_length
  {
     my $a = shift;                          
     my $b = shift;                          
     return _longestCommonSubsequence( $a, $b, 1, @_ );
  }
  sub LCSidx
  {
     my $a= shift @_;
     my $b= shift @_;
     my $match= _longestCommonSubsequence( $a, $b, 0, @_ );
     my @am= grep defined $match->[$_], 0..$#$match;
     my @bm= @{$match}[@am];
     return \@am, \@bm;
  }
  sub compact_diff
  {
     my $a= shift @_;
     my $b= shift @_;
     my( $am, $bm )= LCSidx( $a, $b, @_ );
     my @cdiff;
     my( $ai, $bi )= ( 0, 0 );
     push @cdiff, $ai, $bi;
     while( 1 ) {
        while(  @$am  &&  $ai == $am->[0]  &&  $bi == $bm->[0]  ) {
          shift @$am;
          shift @$bm;
          ++$ai, ++$bi;
        }
        push @cdiff, $ai, $bi;
        last   if  ! @$am;
        $ai = $am->[0];
        $bi = $bm->[0];
        push @cdiff, $ai, $bi;
     }
     push @cdiff, 0+@$a, 0+@$b
        if  $ai < @$a || $bi < @$b;
     return wantarray ? @cdiff : \@cdiff;
  }
  sub diff
  {
     my $a      = shift;    
     my $b      = shift;    
     my $retval = [];
     my $hunk   = [];
     my $discard = sub {
        push @$hunk, [ '-', $_[0], $a->[ $_[0] ] ];
     };
     my $add = sub {
        push @$hunk, [ '+', $_[1], $b->[ $_[1] ] ];
     };
     my $match = sub {
        push @$retval, $hunk
          if 0 < @$hunk;
        $hunk = []
     };
     traverse_sequences( $a, $b,
        { MATCH => $match, DISCARD_A => $discard, DISCARD_B => $add }, @_ );
     &$match();
     return wantarray ? @$retval : $retval;
  }
  sub sdiff
  {
     my $a      = shift;    
     my $b      = shift;    
     my $retval = [];
     my $discard = sub { push ( @$retval, [ '-', $a->[ $_[0] ], "" ] ) };
     my $add = sub { push ( @$retval, [ '+', "", $b->[ $_[1] ] ] ) };
     my $change = sub {
        push ( @$retval, [ 'c', $a->[ $_[0] ], $b->[ $_[1] ] ] );
     };
     my $match = sub {
        push ( @$retval, [ 'u', $a->[ $_[0] ], $b->[ $_[1] ] ] );
     };
     traverse_balanced(
        $a,
        $b,
        {
          MATCH     => $match,
          DISCARD_A => $discard,
          DISCARD_B => $add,
          CHANGE    => $change,
        },
        @_
     );
     return wantarray ? @$retval : $retval;
  }
  ########################################
  my $Root= __PACKAGE__;
  package Algorithm::Diff::_impl;
  use strict;
  sub _Idx()  { 0 } 
  sub _End()  { 3 } 
  sub _Same() { 4 } 
  sub _Base() { 5 } 
  sub _Pos()  { 6 } 
  sub _Off()  { 7 } 
  sub _Min() { -2 } 
  sub Die
  {
     require Carp;
     Carp::confess( @_ );
  }
  sub _ChkPos
  {
     my( $me )= @_;
     return   if  $me->[_Pos];
     my $meth= ( caller(1) )[3];
     Die( "Called $meth on 'reset' object" );
  }
  sub _ChkSeq
  {
     my( $me, $seq )= @_;
     return $seq + $me->[_Off]
        if  1 == $seq  ||  2 == $seq;
     my $meth= ( caller(1) )[3];
     Die( "$meth: Invalid sequence number ($seq); must be 1 or 2" );
  }
  sub getObjPkg
  {
     my( $us )= @_;
     return ref $us   if  ref $us;
     return $us . "::_obj";
  }
  sub new
  {
     my( $us, $seq1, $seq2, $opts ) = @_;
     my @args;
     for( $opts->{keyGen} ) {
        push @args, $_   if  $_;
     }
     for( $opts->{keyGenArgs} ) {
        push @args, @$_   if  $_;
     }
     my $cdif= Algorithm::Diff::compact_diff( $seq1, $seq2, @args );
     my $same= 1;
     if(  0 == $cdif->[2]  &&  0 == $cdif->[3]  ) {
        $same= 0;
        splice @$cdif, 0, 2;
     }
     my @obj= ( $cdif, $seq1, $seq2 );
     $obj[_End] = (1+@$cdif)/2;
     $obj[_Same] = $same;
     $obj[_Base] = 0;
     my $me = bless \@obj, $us->getObjPkg();
     $me->Reset( 0 );
     return $me;
  }
  sub Reset
  {
     my( $me, $pos )= @_;
     $pos= int( $pos || 0 );
     $pos += $me->[_End]
        if  $pos < 0;
     $pos= 0
        if  $pos < 0  ||  $me->[_End] <= $pos;
     $me->[_Pos]= $pos || !1;
     $me->[_Off]= 2*$pos - 1;
     return $me;
  }
  sub Base
  {
     my( $me, $base )= @_;
     my $oldBase= $me->[_Base];
     $me->[_Base]= 0+$base   if  defined $base;
     return $oldBase;
  }
  sub Copy
  {
     my( $me, $pos, $base )= @_;
     my @obj= @$me;
     my $you= bless \@obj, ref($me);
     $you->Reset( $pos )   if  defined $pos;
     $you->Base( $base );
     return $you;
  }
  sub Next {
     my( $me, $steps )= @_;
     $steps= 1   if  ! defined $steps;
     if( $steps ) {
        my $pos= $me->[_Pos];
        my $new= $pos + $steps;
        $new= 0   if  $pos  &&  $new < 0;
        $me->Reset( $new )
     }
     return $me->[_Pos];
  }
  sub Prev {
     my( $me, $steps )= @_;
     $steps= 1   if  ! defined $steps;
     my $pos= $me->Next(-$steps);
     $pos -= $me->[_End]   if  $pos;
     return $pos;
  }
  sub Diff {
     my( $me )= @_;
     $me->_ChkPos();
     return 0   if  $me->[_Same] == ( 1 & $me->[_Pos] );
     my $ret= 0;
     my $off= $me->[_Off];
     for my $seq ( 1, 2 ) {
        $ret |= $seq
          if  $me->[_Idx][ $off + $seq + _Min ]
          <   $me->[_Idx][ $off + $seq ];
     }
     return $ret;
  }
  sub Min {
     my( $me, $seq, $base )= @_;
     $me->_ChkPos();
     my $off= $me->_ChkSeq($seq);
     $base= $me->[_Base] if !defined $base;
     return $base + $me->[_Idx][ $off + _Min ];
  }
  sub Max {
     my( $me, $seq, $base )= @_;
     $me->_ChkPos();
     my $off= $me->_ChkSeq($seq);
     $base= $me->[_Base] if !defined $base;
     return $base + $me->[_Idx][ $off ] -1;
  }
  sub Range {
     my( $me, $seq, $base )= @_;
     $me->_ChkPos();
     my $off = $me->_ChkSeq($seq);
     if( !wantarray ) {
        return  $me->[_Idx][ $off ]
          -   $me->[_Idx][ $off + _Min ];
     }
     $base= $me->[_Base] if !defined $base;
     return  ( $base + $me->[_Idx][ $off + _Min ] )
        ..  ( $base + $me->[_Idx][ $off ] - 1 );
  }
  sub Items {
     my( $me, $seq )= @_;
     $me->_ChkPos();
     my $off = $me->_ChkSeq($seq);
     if( !wantarray ) {
        return  $me->[_Idx][ $off ]
          -   $me->[_Idx][ $off + _Min ];
     }
     return
        @{$me->[$seq]}[
             $me->[_Idx][ $off + _Min ]
          ..  ( $me->[_Idx][ $off ] - 1 )
        ];
  }
  sub Same {
     my( $me )= @_;
     $me->_ChkPos();
     return wantarray ? () : 0
        if  $me->[_Same] != ( 1 & $me->[_Pos] );
     return $me->Items(1);
  }
  my %getName;
     %getName= (
        same => \&Same,
        diff => \&Diff,
        base => \&Base,
        min  => \&Min,
        max  => \&Max,
        range=> \&Range,
        items=> \&Items, 
     );
  sub Get
  {
     my $me= shift @_;
     $me->_ChkPos();
     my @value;
     for my $arg (  @_  ) {
        for my $word (  split ' ', $arg  ) {
          my $meth;
          if(     $word !~ /^(-?\d+)?([a-zA-Z]+)([12])?$/
             ||  not  $meth= $getName{ lc $2 }
          ) {
             Die( $Root, ", Get: Invalid request ($word)" );
          }
          my( $base, $name, $seq )= ( $1, $2, $3 );
          push @value, scalar(
             4 == length($name)
                ? $meth->( $me )
                : $meth->( $me, $seq, $base )
          );
        }
     }
     if(  wantarray  ) {
        return @value;
     } elsif(  1 == @value  ) {
        return $value[0];
     }
     Die( 0+@value, " values requested from ",
        $Root, "'s Get in scalar context" );
  }
  my $Obj= getObjPkg($Root);
  no strict 'refs';
  for my $meth (  qw( new getObjPkg )  ) {
     *{$Root."::".$meth} = \&{$meth};
     *{$Obj ."::".$meth} = \&{$meth};
  }
  for my $meth (  qw(
     Next Prev Reset Copy Base Diff
     Same Items Range Min Max Get
     _ChkPos _ChkSeq
  )  ) {
     *{$Obj."::".$meth} = \&{$meth};
  }
};
{
  package Algorithm::LCSS;
  use strict;
  {
    no strict 'refs';
    *traverse_sequences = \&Algorithm::Diff::traverse_sequences;
  }
  sub _tokenize { [split //, $_[0]] }
  sub CSS {
     my $is_array = ref $_[0] eq 'ARRAY' ? 1 : 0;
     my ( $seq1, $seq2, @match, $from_match );
     my $i = 0;
     if ( $is_array ) {
        $seq1 = $_[0];
        $seq2 = $_[1];
        traverse_sequences( $seq1, $seq2, {
          MATCH => sub { push @{$match[$i]}, $seq1->[$_[0]]; $from_match = 1 },
          DISCARD_A => sub { do{$i++; $from_match = 0} if $from_match },
          DISCARD_B => sub { do{$i++; $from_match = 0} if $from_match },
        });
     }
     else {
        $seq1 = _tokenize($_[0]);
        $seq2 = _tokenize($_[1]);
        traverse_sequences( $seq1, $seq2, {
          MATCH => sub { $match[$i] .= $seq1->[$_[0]]; $from_match = 1 },
          DISCARD_A => sub { do{$i++; $from_match = 0} if $from_match },
          DISCARD_B => sub { do{$i++; $from_match = 0} if $from_match },
        });
     }
    return \@match;
  }
  sub CSS_Sorted {
     my $match = CSS(@_);
     if ( ref $_[0] eq 'ARRAY' ) {
       @$match = map{$_->[0]}sort{$b->[1]<=>$a->[1]}map{[$_,scalar(@$_)]}@$match
     }
     else {
       @$match = map{$_->[0]}sort{$b->[1]<=>$a->[1]}map{[$_,length($_)]}@$match
     }
    return $match;
  }
  sub LCSS {
     my $is_array = ref $_[0] eq 'ARRAY' ? 1 : 0;
     my $css = CSS(@_);
     my $index;
     my $length = 0;
     if ( $is_array ) {
        for( my $i = 0; $i < @$css; $i++ ) {
          next unless @{$css->[$i]}>$length;
          $index = $i;
          $length = @{$css->[$i]};
        }
     }
     else {
        for( my $i = 0; $i < @$css; $i++ ) {
          next unless length($css->[$i])>$length;
          $index = $i;
          $length = length($css->[$i]);
        }
     }
    return $css->[$index];
  }
};
{
  package Class::Classless;
  use strict;
  use vars qw(@ISA);
  use Carp;
  @ISA = ();
  ###########################################################################
  @Class::Classless::X::ISA = ();
  ###########################################################################
  ###########################################################################
  sub Class::Classless::X::AUTOLOAD {
    my $it = shift @_;
    my $m =  ($Class::Classless::X::AUTOLOAD =~ m/([^:]+)$/s ) 
           ? $1 : $Class::Classless::X::AUTOLOAD;
    croak "Can't call Class::Classless methods (like $m) without an object"
     unless ref $it;  
    my $prevstate;
    $prevstate = ${shift @_}
    if scalar(@_) && defined($_[0]) &&
      ref($_[0]) eq 'Class::Classless::CALLSTATE::SHIMMY'
    ;   
    my $no_fail = $prevstate ? $prevstate->[3] : undef;
    my $i       = $prevstate ? ($prevstate->[1] + 1) : 0;
    my $lineage;
    if($prevstate) {
     $lineage = $prevstate->[2];
    } elsif(defined $it->{'ISA_CACHE'} and ref $it->{'ISA_CACHE'} ){
     $lineage = $it->{'ISA_CACHE'};
    } else {
     $lineage = [ &Class::Classless::X::ISA_TREE($it) ];
    }
    #my @lineage =
    for(; $i < @$lineage; ++$i) {
     if( !defined($no_fail) and exists($lineage->[$i]{'NO_FAIL'}) ) {
      $no_fail = ($lineage->[$i]{'NO_FAIL'} || 0);
     }
     if(     ref($lineage->[$i]{'METHODS'}     || 0)  
      && exists($lineage->[$i]{'METHODS'}{$m})
     ){
      my $v = $lineage->[$i]{'METHODS'}{$m};
      return $v unless defined $v and ref $v;
      if(ref($v) eq 'CODE') { 
        unshift @_, 
         $it,                   
         bless([$m, $i, $lineage, $no_fail, $prevstate ? 1 : 0],
             'Class::Classless::CALLSTATE'
            ),                
        ;
        goto &{ $v }; 
      }
      return @$v if ref($v) eq '_deref_array';
      return $$v if ref($v) eq '_deref_scalar';
      return $v; 
     }
    }
    if($m eq 'DESTROY') { 
    } else {
     if($no_fail || 0) {
      return;
     }
     croak "Can't find ", $prevstate ? 'NEXT method' : 'method',
         " $m in ", $it->{'NAME'} || $it,
         " or any ancestors\n";
    }
  }
  ###########################################################################
  ###########################################################################
  sub Class::Classless::X::DESTROY {
  }
  ###########################################################################
  sub Class::Classless::X::ISA_TREE {
    use strict;
    my $set_cache = 0; 
    if(exists($_[0]{'ISA_CACHE'})) {
     return    @{$_[0]{'ISA_CACHE'}}
      if defined $_[0]{'ISA_CACHE'}
        and ref $_[0]{'ISA_CACHE'};
     $set_cache = 1;
    }
    my $has_mi = 0; 
    my %last_child = ($_[0] => 1); 
    my @tree_nodes;
    {
     my $current;
     my @in_stack = ($_[0]);
     while(@in_stack) {
      next unless
       defined($current = shift @in_stack)
       && ref($current) 
       && ref($current->{'PARENTS'} || 0) 
      ;
      push @tree_nodes, $current;
      $has_mi = 1 if @{$current->{'PARENTS'}} > 1;
      unshift
        @in_stack,
        map {
         if(exists $last_child{$_}) { 
          $last_child{$_} = $current;
          (); 
         } else { 
          $last_child{$_} = $current;
          $_; 
         }
        }
        @{$current->{'PARENTS'}}
      ;
     }
     unless($has_mi) {
      $_[0]{'ISA_CACHE'} = \@tree_nodes if $set_cache;
      return @tree_nodes;
     }
    }
    my @out;
    {
     my $current;
     my @in_stack = ($_[0]);
     while(@in_stack) {
      next unless defined($current = shift @in_stack) && ref($current);
      push @out, $current; 
      unshift
        @in_stack,
        grep(
         (
          defined($_) 
          && ref($_)  
          && $last_child{$_} eq $current,
         ),
         @{$current->{'PARENTS'}}
        )
       if ref($current->{'PARENTS'} || 0) 
      ;
     }
     unless(scalar(@out) == scalar(keys(%last_child))) {
      my %good_ones;
      @good_ones{@out} = ();
      croak
        "ISA tree for " .
        ($_[0]{'NAME'} || $_[0]) .
        " is apparently cyclic, probably involving the nodes " .
        nodelist( grep { ref($_) && !exists $good_ones{$_} }
         values(%last_child) )
        . "\n";
     }
    }
    #print "Contents of out: ", nodelist(@out), "\n";
    $_[0]{'ISA_CACHE'} = \@out if $set_cache;
    return @out;
  }
  ###########################################################################
  sub Class::Classless::X::can { 
    my($it, $m) = @_[0,1];
    return undef unless ref $it;
    croak "undef is not a valid method name"       unless defined($m);
    croak "null-string is not a valid method name" unless length($m);
    foreach my $o (&Class::Classless::X::ISA_TREE($it)) {
     return 1
      if  ref($o->{'METHODS'} || 0)   
      && exists $o->{'METHODS'}{$m};
    }
    return 0;
  }
  ###########################################################################
  sub Class::Classless::X::isa { 
    return unless ref($_[0]) && ref($_[1]);
    return scalar(grep {$_ eq $_[1]} &Class::Classless::X::ISA_TREE($_[0])); 
  }
  ###########################################################################
  sub nodelist { join ', ', map { "" . ($_->{'NAME'} || $_) . ""} @_ }
  ###########################################################################
  ###########################################################################
  ###########################################################################
  @Class::Classless::ISA = ();
  sub Class::Classless::CALLSTATE::found_name { $_[0][0] }
  sub Class::Classless::CALLSTATE::found_depth { $_[0][1] }
  sub Class::Classless::CALLSTATE::lineage { @{$_[0][2]} }
  sub Class::Classless::CALLSTATE::target { $_[0][2][  0          ] }
  sub Class::Classless::CALLSTATE::home   { $_[0][2][  $_[0][1]   ] }
  sub Class::Classless::CALLSTATE::sub_found {
    $_[0][2][  $_[0][1]   ]{'METHODS'}{ $_[0][0] }
  }  
  sub Class::Classless::CALLSTATE::no_fail          {  $_[0][3]         }
  sub Class::Classless::CALLSTATE::set_no_fail_true {  $_[0][3] = 1     }
  sub Class::Classless::CALLSTATE::set_fail_false   {  $_[0][3] = 0     }
  sub Class::Classless::CALLSTATE::set_fail_undef   {  $_[0][3] = undef }
  sub Class::Classless::CALLSTATE::via_next         {  $_[0][4] }
  sub Class::Classless::CALLSTATE::NEXT {
    #croak "NEXT needs at least one argument: \$cs->NEXT('method'...)"
    my $cs = shift @_;
    my $m  = shift @_; 
    $m = $cs->[0] unless defined $m; 
    ($cs->[2][0])->$m(
     bless( \$cs, 'Class::Classless::CALLSTATE::SHIMMY' ),
     @_
    );
  }
  ###########################################################################
};
