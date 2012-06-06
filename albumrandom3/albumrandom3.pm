# Gmusicbrowser: Copyright (C) 2005- Quentin Sculo <squentin@free.fr>
# Albumrandom: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
# This file is a plugin to Gmusicbrowser.

# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin ALBUMRANDOM3
name	Albumrandom3
title	AlbumRandom plugin (v3)
desc	Albumrandom plays albums according to set weighted random.
=cut


# TODO

package GMB::Plugin::ALBUMRANDOM3;
use strict;
use warnings;
use utf8;

my $AR_VNUM = 'pre-3.0';
my $AR_ICON = 'plugin-albumrandom3';
my $AlbumrandomIsOn = 0;
my $handle={};

my $CUR_GID=-1;
my $oldsongid=-1;
my $LASTUSED_WR;
my $sub;

use constant
{	OPT	=> 'PLUGIN_ALBUMRANDOM_',
};

::SetDefaultOptions(OPT, UseJustOneMode => 1, OnUserAction => 'continue_from', UseSpecificStraightMode => 0);

my %ContinueModes = ( continue_from => 'Continue with current album', disable_ar => 'Turn off albumrandom', create_new => 'Generate new album');

sub Start
{
	$::Options{OPT.'JustOneRandomMode'} = ((sort keys %{$::Options{SavedWRandoms}})[0]) unless (defined $::Options{OPT.'JustOneRandomMode'});
	$::Options{OPT.'StraightPlayMode'} = ((sort keys %{$::Options{SavedSorts}})[0]) unless (defined $::Options{OPT.'StraightPlayMode'});
	AddARToPlayer();
	::Watch($handle, PlayingSong => \&SongChanged);

}
sub Stop
{
	$AlbumrandomIsOn = 0;
	::HasChanged('AlbumrandomOn');
	::UnWatch($handle,'PlayingSong');	
}

sub prefbox
{
	my $vbox;
	
	my @p;
	push @p, $_ for (sort keys %{$::Options{SavedWRandoms}});
	my $pmcombo= ::NewPrefCombo( OPT.'JustOneRandomMode', \@p);
	my $pmcheck = ::NewPrefCheckButton(OPT.'UseJustOneMode','Weight always with playmode: ');
	
	@p = ();
	push @p, $_ for (sort keys %{$::Options{SavedSorts}});
	my $pmcombo2= ::NewPrefCombo( OPT.'StraightPlayMode', \@p);
	my $pmcheck2 = ::NewPrefCheckButton(OPT.'UseSpecificStraightMode','Play albums always with playmode: ');

	@p = values %ContinueModes;
	my $pmcombo3= ::NewPrefCombo( OPT.'OnUserAction', \@p);
	my $pmlabel3=Gtk2::Label->new('When manually changing to a different album: ');
	
	$vbox = ::Vpack([$pmcheck,$pmcombo],[$pmcheck2,$pmcombo2],[$pmlabel3,$pmcombo3]);
	return $vbox;
}

sub SongChanged
{
	return unless ($AlbumrandomIsOn);
	return if ($oldsongid == $::SongID);
	return if (scalar@$::Queue);
	
	$oldsongid = $::SongID;
	my $nowGID = Songs::Get_gid($::SongID,'album');
	my $nextSongs = ::GetNextSongs();
	my $nextGID = Songs::Get_gid($nextSongs,'album') if (defined $nextSongs);
	
	if ((not defined $nextGID) and (!GetNextAlbum())) {ToggleAlbumrandom(0);}
	elsif (($nowGID != $CUR_GID) or ($nextGID != $CUR_GID))
	{
		my $handled = 0;

		if (($::Options{OPT.'OnUserAction'} eq $ContinueModes{'disable_ar'}) and ($nowGID != $CUR_GID))	{
			ToggleAlbumrandom(0); 
			$handled = 1;
		}
		elsif ($::Options{OPT.'OnUserAction'} eq $ContinueModes{'continue_from'}) {
			$CUR_GID = $nowGID;
			if ($nextGID == $CUR_GID) {$handled = 1;}
		}
		
		if (!$handled){
			ToggleAlbumrandom(0) unless (GetNextAlbum());
		}
	}
}

sub Random::MakeGroupScoreFunction_Average
{	my ($self,$field)=@_;
	my ($keycode,$multi)= Songs::LookupCode($field, 'hash','hashm', [ID => '$_']);
	unless ($keycode || $multi) { warn "MakeGroupScoreFunction error : can't find code for field $field\n"; return } #return dummy sub ?
	($keycode,my $keyafter)= split / +---- +/,$keycode||$multi,2;
	if ($keyafter) { warn "MakeGroupScoreFunction with field $field is not supported yet\n"; return } #return dummy sub ?
	my ($before,$score)=$self->make;
	my $calcIDscore= $multi ? 'my $IDscore='.$score.'; for my $key ('.$keycode.') {$score{$key}+=$IDscore}' : "\$score\{$keycode}\{score}+=$score; \$score\{$keycode}\{items}+=1;";
	my $code= $before.'; sub { my %score; for (@{$_[0]}) { '.$calcIDscore.' } return \%score; }';
	my $sub=eval $code;
	if ($@) { warn "Error in eval '$code' :\n$@"; return }
	return $sub;
}

sub GetNextAlbum
{
	my $m = ($::Options{OPT.'UseJustOneMode'})? $::Options{OPT.'JustOneRandomMode'} : $::Options{OPT.'RandomMode'}; 
	
	if ((not defined $LASTUSED_WR) or (not defined $sub) or ($m ne $LASTUSED_WR))
	{
		my $R = Random->new($::Options{SavedWRandoms}{$m});
		$sub = $R->MakeGroupScoreFunction_Average('album');
		$LASTUSED_WR = $m;
	}
	my $h=$sub->($::ListPlay);
	my %probhash;
	
	return 0 if ((!scalar keys %$h) or (((scalar keys %$h) == 1) and (defined $$h{$CUR_GID})));
	
	my $total=0;
	for my $gid (keys %$h)
	{
		next unless ($h->{$gid}{items});
		next if ($gid == $CUR_GID);
		
		my $curProp = $h->{$gid}{score} || 0;
		$probhash{$gid} = ($curProp/$h->{$gid}{items});
		$total += $probhash{$gid};
	}

	my $found=-1;
	my $goneprob=0;
	my $random = rand($total);

	for my $gid (keys %probhash)
	{
		$goneprob += $probhash{$gid};
		if ($goneprob > $random) { $found = $gid; last;};
	}
 	return 0 unless ($found > -1);
 	
	my $tracklist=AA::GetIDs('album',$found);
	my $strplaymode = $::Options{Sort}; 
	if ($::Options{OPT.'UseSpecificStraightMode'}){	
		$strplaymode = $::Options{SavedSorts}{$::Options{OPT.'StraightPlayMode'}}
	}
	elsif ($::Options{Sort}=~m/random|shuffle/) {
			$strplaymode = $::Options{SavedSorts}{$::Options{Sort_LastOrdered}} || $::Options{SavedSorts}{$::Options{OPT.'StraightPlayMode'}};
	} 

	$CUR_GID = $found;
	::Enqueue(Songs::FindFirst($tracklist,$strplaymode));
	::Select('sort' => $strplaymode) unless ($strplaymode eq $::Options{Sort});
	
	return 1;
}

sub AddARToPlayer()
{
	# sort - widgets
	$::Command{MenuPlayOrder}[0] = sub {GMB::Plugin::ALBUMRANDOM3::ARSortMenu();};
	
	# playmode - icon
	${$Layout::Widgets{Sort}->{stock}}{albumrandom} = $AR_ICON;
	$Layout::Widgets{Sort}->{event} = 'Sort SavedWRandoms SavedSorts AlbumrandomOn';
	$Layout::Widgets{Sort}->{'state'} = sub 
		{
			if ($AlbumrandomIsOn) {'albumrandom'}
			else
			{
				my $s=$::Options{'Sort'};
				if ($s=~m/^random:/) { 'random'}
				elsif ($s eq 'shuffle') { 'shuffle'}
				else { 'sorted'}
			}
		};
}

sub ToggleAlbumrandom
{
	my $toggle = shift; 
	$toggle = (($AlbumrandomIsOn)? 0 : 1) unless (defined $toggle);

	$AlbumrandomIsOn = $toggle; 
	::HasChanged('AlbumrandomOn');
	if ($AlbumrandomIsOn){
		if (!GetNextAlbum()) { ToggleAlbumrandom(0);}
	}
	
	return 1;
}

sub ARSortMenu
{
	my $nopopup= $_[0];
	my $menu = $_[0] || Gtk2::Menu->new;

	my $return=0;
	$return=1 unless @_;
	my $check=$::Options{Sort};
	my $found;
	my $callback=sub { ::Select('sort' => $_[1]); };
	my $append=sub
	 {	my ($menu,$name,$sort,$true,$cb)=@_;
		$cb||=$callback;
		$true=($sort eq $check) unless defined $true;
		my $item = Gtk2::CheckMenuItem->new_with_label($name);
		$item->set_draw_as_radio(1);
		$item->set_active($found=1) if $true;
		$item->signal_connect (activate => $cb, $sort );
		$menu->append($item);
	 };

	my $submenu= Gtk2::Menu->new;
	my $sitem = Gtk2::MenuItem->new(_"Weighted Random");
	for my $name (sort keys %{$::Options{SavedWRandoms}})
	{	$append->($submenu,$name, $::Options{SavedWRandoms}{$name} );
	}
	my $editcheck=(!$found && $check=~m/^random:/);
	$append->($submenu,_"Custom...", undef, $editcheck, sub
		{	::EditWeightedRandom(undef,$::Options{Sort},undef, \&::Select_sort);
		});
	$sitem->set_submenu($submenu);
	$menu->prepend($sitem);


	## albumrandom
	if ($::Options{OPT.'UseJustOneMode'})
	{
		my $aritem = Gtk2::CheckMenuItem->new_with_label('Albumrandom');
		$aritem->set_draw_as_radio(1);
		$aritem->set_active(1) if ($AlbumrandomIsOn);
		$aritem->signal_connect (activate => sub {ToggleAlbumrandom();} );
		$menu->prepend($aritem);
	}
	else
	{
		my $arsubmenu= Gtk2::Menu->new;
		my $aritem = Gtk2::MenuItem->new(_"Albumrandom");
	
		for my $name (sort keys %{$::Options{SavedWRandoms}}) 
		{	
			my $item = Gtk2::CheckMenuItem->new_with_label($name);
			$item->set_draw_as_radio(1);
			my $true = (($AlbumrandomIsOn) and ($name eq $::Options{OPT.'RandomMode'}))? 1 : 0;
			$item->set_active($true);
			$item->signal_connect (activate => sub 
				{ 
					$::Options{OPT.'RandomMode'} = $name; 
					ToggleAlbumrandom(($true)? undef : 1); 
				});
			$arsubmenu->append($item);			
		}
		$aritem->set_submenu($arsubmenu);
		$menu->prepend($aritem);
	}

	$append->($menu,_"Shuffle",'shuffle') unless $check eq 'shuffle';

	if ($check=~m/shuffle/)
	{ my $item=Gtk2::MenuItem->new(_"Re-shuffle");
	  $item->signal_connect(activate => $callback, $check );
	  $menu->append($item);
	}

	{ my $item=Gtk2::CheckMenuItem->new(_"Repeat");
	  $item->set_active($::Options{Repeat});
	  $item->set_sensitive(0) if $::RandomMode;
	  $item->signal_connect(activate => sub { ::SetRepeat($_[0]->get_active); } );
	  $menu->append($item);
	}

	$menu->append(Gtk2::SeparatorMenuItem->new); #separator between random and non-random modes

	$append->($menu,_"List order", '' ) if defined $::ListMode;
	for my $name (sort keys %{$::Options{SavedSorts}})
	{	$append->($menu,$name, $::Options{SavedSorts}{$name} );
	}
	$append->($menu,_"Custom...",undef,!$found,sub
		{	::EditSortOrder(undef,$::Options{Sort},undef, \&::Select_sort );
		});
	$menu->show_all;
	return $menu if $nopopup;
	my $event=Gtk2->get_current_event;
	my ($button,$pos)= $event->isa('Gtk2::Gdk::Event::Button') ? ($event->button,\&::menupos) : (0,undef);
	$menu->popup(undef,undef,$pos,undef,$button,$event->time);
}



1