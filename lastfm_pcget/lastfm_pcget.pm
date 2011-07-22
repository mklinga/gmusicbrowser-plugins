# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin LASTFM_PCGET
name	lastfm_pcGet
title	playcount fetcher
desc	Downloads playcount for currently playing song
=cut

#TODO
#make sure that don't try to correct songs that have already been corrected through 'correct all'!

package GMB::Plugin::LASTFM_PCGET;
use strict;
use warnings;
use constant
{	CLIENTID => 'gmb', VERSION => '0.1',
	OPT => 'PLUGIN_LASTFM_PCGET_',#used to identify the plugin's options
	APIKEY => 'f39afc8f749e2bde363fc8d3cfd02aae',
};


::SetDefaultOptions(OPT, checkcorrections => 1);

use Digest::MD5 'md5_hex';
require $::HTTP_module;

my $self=bless {},__PACKAGE__;
my $Log=Gtk2::ListStore->new('Glib::String');
my $waiting;
my $oldID = -1;
my $Datafile = $::HomeDir.'lastfm_corrections';
my $Banfile = $::HomeDir.'lastfm_corrections.banned';
my @corrections;

use base 'Gtk2::Box';
use base 'Gtk2::Dialog';
use utf8;

my @checks;
my @banned;

my $s2;

sub Start
{
	::Watch($self,PlayingSong=> \&SongChanged);
	loadCorrections();
	loadBanned();
}
sub Stop
{
	$waiting->abort if ($waiting);
	::UnWatch_all($self);
}

sub prefbox
{
	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $vbox2=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $entry1=::NewPrefEntry(OPT.'USER',_"Username: ", sizeg1 => $sg1,sizeg2=>$sg2);
	

	my $listcombo= ::NewPrefCombo( OPT.'pcvalues', { always => 'Always set last.fm value', biggest => 'Set bigger amount', smallest => 'Set smaller amount',});
	my $l=Gtk2::Label->new('How to deal with different playcount values: ');

	my $listcombo2= ::NewPrefCombo( OPT.'multiple', { playing => 'Set only playing tracks playcount', split_evenly => 'Split playcount evenly', separate => 'Set every tracks playcount separately', as_one => 'Handle different songs as one',});
	my $l2=Gtk2::Label->new('In case of multiple tracks with same artist and title: ');

	my $button2=Gtk2::Button->new();
	$button2->signal_connect(clicked => \&Correct);
	$button2->set_label("Show Corrections");

	my $check=::NewPrefCheckButton(OPT."checkcorrections",'Check for corrections',horizontal=>1);
	my $cl=Gtk2::Label->new();
	
	if (scalar@corrections == 1){$cl->set_label(" ".scalar@corrections." correction noted");}
	else {$cl->set_label(" ".scalar@corrections." corrections noted");}

	my $listcombo3= ::NewPrefCombo( OPT.'titlechange', { change_one => 'Change only the noted track', change_all => 'Change all songs with same artist/title',});
	my $l3=Gtk2::Label->new('When correcting track title: ');

	my $listcombo4= ::NewPrefCombo( OPT.'artistchange', {change_one => 'Change only for the noted track', change_all => 'Change all tracks from artist',});
	my $l4=Gtk2::Label->new('When correcting artist: ');
	

	my $frame1=Gtk2::Frame->new(_" Playcount fetching ");
	my $frame2=Gtk2::Frame->new(_" Track/Artist correction ");

	$vbox=::Vpack($entry1,[$l,$listcombo],[$l2,$listcombo2]);
	$vbox2=::Vpack($check,[$l3,$listcombo3,$l4,$listcombo4],[$button2,$cl]);

	$frame1->add($vbox);
	$frame2->add($vbox2);
	
	my $fi = ::Vpack( $frame2, $frame1);
	$fi->add(::LogView($Log));
	
	return $fi;
}

sub SongChanged
{
	return if ($oldID == $::SongID);
	
	$oldID = $::SongID;
	Sync();
}


sub Log
{	my $text=$_[0];
	$Log->set( $Log->prepend,0, localtime().'  '.$text );
	warn "$text\n" if $::debug;
	if (my $iter=$Log->iter_nth_child(undef,50)) { $Log->remove($iter); }
}

sub loadCorrections()
{
	open(my $fh, '<', $Datafile) or return;
	@corrections = <$fh>;
	close($fh);
}

sub saveCorrections()
{
		return 'no datafile' unless defined $Datafile;

		my $content = '';
		
		foreach my $a (@corrections) { if ($a =~ m/(.+)\t(.+)\t(.+)/) {$content .= $a;}}

		open my $fh,'>',$Datafile or warn "Error opening '$Datafile' for writing : $!\n";
		print $fh $content   or warn "Error writing to '$Datafile' : $!\n";
		close $fh;
}

sub checkCorrection()
{
	return if ($waiting);

	my $artist = Songs::Get($::SongID,'artist');
	my $title = Songs::Get($::SongID,'title');

	my $url = 'http://ws.audioscrobbler.com/2.0/?method=track.getcorrection&artist='.::url_escapeall($artist).'&track='.::url_escapeall($title).'&api_key=b25b959554ed76058ac220b7b2e0a026';

	my $correcttrack = '';
	my $correctartist = '';
	
	my $cb=sub
	{	
		$waiting=undef;
		my @r=(defined $_[0])? split "\012",$_[0] : ();
		foreach my $a (@r) 
		{
			#if there is no corrections, <name> won't exist
			#if there is, it's always track first, then artist
			
			if ( $a =~ m/<name>(.+)<\/name>/)
			{
				 if ($correcttrack eq '') { $correcttrack = $1; }
				 elsif ($correctartist eq '') { $correctartist = $1; }
			}
		}
		
		if ($correcttrack ne '') 
		{
			my $new_correction = Songs::Get($::SongID,'fullfilename')."\t".$correctartist."\t".$correcttrack."\n";
			my $is_banned = 0;

			#then we check if current file has been banned or if it's already on @corrections
			foreach my $bb (@banned) { if ($bb eq $new_correction) { $is_banned = 1; }} 
			foreach my $bb (@corrections) { if ($bb eq $new_correction) { $is_banned = 1; }} 

			if ($is_banned == 0)
			{
				push(@corrections,$new_correction); 
				saveCorrections();
			} 
		}
	};
	my $waiting=Simple_http::get_with_cb(cb => $cb,url => $url,post => '');
}
sub Sync()
{
	return if ($waiting);

	my $user=$::Options{OPT.'USER'};

	if ($user eq '') { return;}

	my $artist = Songs::GetTagValue($::SongID,'artist');
	my $album = Songs::GetTagValue($::SongID,'album');
	my $title = Songs::GetTagValue($::SongID,'title');

	my $url = 'http://ws.audioscrobbler.com/2.0/?method=track.getinfo&username='.$user.'&api_key='.APIKEY.'&artist='.::url_escapeall($artist).'&track='.::url_escapeall($title);
	my $foundupc = 0;
	my $pcvalue = 0;
	my $multiple = 0;

	my $multifilter=Filter->newadd(1,'title:e:'.$title, 'artist:e:'.$artist)->filter;
	
	#always => 'Always set last.fm value', 
	#biggest => 'Set bigger amount', 
	#smallest => 'Set smaller amount'
	
	#playing => 'Set only playing tracks playcount', 
	#split_evenly => 'Split playcount evenly', 
	#separate => 'Set every tracks playcount separately', 
	#as_one => 'Handle different songs as one'
	
	if ($::Options{OPT.'pcvalues'} eq 'always') { $pcvalue = 1;}
	elsif ($::Options{OPT.'pcvalues'} eq 'biggest') { $pcvalue = 2;}
	elsif ($::Options{OPT.'pcvalues'} eq 'smallest') { $pcvalue = 3;}

	if ($::Options{OPT.'multiple'} eq 'playing') { $multiple = 1;}
	elsif ($::Options{OPT.'multiple'} eq 'split_evenly') { $multiple = 2;}
	elsif ($::Options{OPT.'multiple'} eq 'separate') { $multiple = 3;}
	elsif ($::Options{OPT.'multiple'} eq 'as_one') { $multiple = 4;}

	
	my $total = 0;
	my $biggest = 0;
	my $smallest = 0;
	my $avg = 0;
	
	my $oc = 0;
	my @changeID;
	my @changevalue;
	
	foreach my $a (@$multifilter)
	{	
		my $pc = Songs::Get($a,'playcount');
		$total += $pc;
		if ($pc < $smallest) { $smallest = $pc; }
		if ($pc > $biggest) { $biggest = $pc; }
	}
	
	$avg = int(($total/scalar@$multifilter)+0.5);

	if ($multiple == 1) { $oc = Songs::Get($::SongID,'playcount');}
	elsif ($multiple == 2) 
	{ 
		if ($pcvalue == 1) {$oc = Songs::Get($::SongID,'playcount');}
		elsif ($pcvalue == 2) {$oc = $biggest;}
		elsif ($pcvalue == 3) {$oc = $smallest;}
	}
	elsif ($multiple == 4){ $oc = $avg	}


	my $cb=sub
	{	
		$waiting=undef;
		my @r=(defined $_[0])? split "\012",$_[0] : ();
		foreach my $a (@r) 
		{
			if ( $a =~ m/<userplaycount>(\d+)<\/userplaycount>/)
			{
					$foundupc = 1;
					my $userplaycount = $1;
				
					#always set last.fm value
					if ($pcvalue == 1)
					{
						if ($multiple == 1)	{ if ($userplaycount != $oc) {push(@changeID,$::SongID); push(@changevalue,$userplaycount);}}
						elsif ($multiple == 2)	#even split
						{
							if ((scalar@$multifilter == 1) and ($userplaycount != $oc)) {push(@changeID,$::SongID); push(@changevalue,$userplaycount);}
							elsif (scalar@$multifilter > 1)
							{
								my $whole = int($userplaycount/scalar@$multifilter);
								my $rest = $userplaycount%scalar@$multifilter;

								foreach my $b (@$multifilter)
								{
									push(@changeID,$b); 
									if ($rest > 0) { push(@changevalue,($whole+1)); $rest--; }
									else { push(@changevalue,($whole));}
								}
							}
						}
						elsif (($multiple == 3) or ($multiple == 4))#separate or as_one
						{
							foreach my $b (@$multifilter){push(@changeID,$b);push(@changevalue,$userplaycount);	}
						}
					}
					else #set biggest/smallest value
					{
						my $modifier = 1;#smallest
						$modifier = -1 if ($pcvalue == 2);#biggest
						
						if ($multiple == 1)#current only
						{
							if ($modifier*($oc-$userplaycount) < 0) 
							{ 
								foreach my $b (@$multifilter){push(@changeID,$b);push(@changevalue,$oc);}							
							}
							else {foreach my $b (@$multifilter){push(@changeID,$b);push(@changevalue,$userplaycount);}}
						}
						elsif ($multiple == 2)#split even
						{
							my $whole;
							my $rest;
							if ($modifier*($oc-$userplaycount) < 0) 
							{
								$whole = int($oc/scalar@$multifilter);
								$rest = $oc%scalar@$multifilter;
							}
							else
							{
								$whole = int($userplaycount/scalar@$multifilter);
								$rest = $userplaycount%scalar@$multifilter;
							}

							foreach my $b (@$multifilter)
							{
								push(@changeID,$b); 
								push(@changevalue,($whole+$rest));
								if ($rest > 0) { $rest--; }
							}
						}
						elsif ($multiple == 3)# each track separate
						{
							foreach my $b (@$multifilter)
							{
								my $curoc = Songs::Get($b,'playcount');
								if ($modifier*($curoc-$userplaycount) > 0)
								{
									#only change if last.fm has wanted value 
									push(@changeID,$b); 
									push(@changevalue,$userplaycount);
								}
							}
						}
						elsif ($multiple == 4)#handle as one
						{
							my $curoc;
							if ($modifier*($oc-$userplaycount) < 0)	{$curoc = $oc;}
							else {$curoc = $userplaycount; }

							foreach my $b (@$multifilter)
							{
								push(@changeID,$b); 
								push(@changevalue,$curoc);
							}
						}
					}				
			}
		}
		
		if ($foundupc == 0) {Log('No previous playcount found for '.$artist.' - '.$title);}
		elsif (scalar@changeID > 0)
		{
			for (my $c=0;$c<(scalar@changeID);$c++)
			{
				Songs::Set($changeID[$c],'playcount',$changevalue[$c]);
				my $num = '';
				if (scalar@changeID > 1) { $num = '['.($c+1).'/'.scalar@changeID.'] '; }
				Log($num."Set playcount to ".$changevalue[$c]." for ".Songs::Get($changeID[$c],'artist')." - ".Songs::Get($changeID[$c],'album')." - ".Songs::Get($changeID[$c],'title'));
			}
		}
		else { Log("Nothing to change for ".$artist." - ".$album." - ".$title) }
		
		if ($::Options{OPT.'checkcorrections'} == 1) {checkCorrection();}
	};
	my $waiting=Simple_http::get_with_cb(cb => $cb,url => $url,post => '');
}
sub Correct
{
	$s2 = bless(Gtk2::Dialog->new(_"last.fm suggestions",undef,'destroy-with-parent'));
	@checks = ();
	
	$s2->set_default_size(700, 400);
	$s2->set_position('center-always');
	$s2->set_border_width(6);

	# Contents: textentry, searchbutton, stopbutton and scrollwindow (for radiobuttons).
	$s2->{selall}= my $selall = ::NewIconButton('gtk-select-all', _"Select all");
	$s2->{selnone}	= my $selnone	  = ::NewIconButton('gtk-clear', _"Select none");
	$s2->{remsel}= my $remsel = ::NewIconButton('gtk-delete', _"Hide selected");
	$s2->{corsel}	= my $corsel	  = ::NewIconButton('gtk-save', _"Correct selected");
	$s2->{close}= my $close = ::NewIconButton('gtk-close', _"Close");
	$s2->{label1} = my $label1 = Gtk2::Label->new('These are last.fm\'s suggestions for corrections');
	$s2->{vbox}	= my $vbox = Gtk2::VBox->new(0,0);
	
	my $scrwin = Gtk2::ScrolledWindow->new();
	$scrwin->set_policy('automatic', 'automatic');
	$scrwin->add_with_viewport($vbox);
	$s2->get_content_area()->add( ::Vpack($label1,'_', $scrwin,[$selall, $selnone, $remsel, $corsel,$close]) );

	foreach my $a (@corrections)
	{
		if ($a =~ m/(.+)\t(.+)\t(.+)/)
		{
			push(@checks, Gtk2::CheckButton->new(Songs::Get(Songs::FindID($1),'artist')." - ".Songs::Get(Songs::FindID($1),'title')." -> ".$2." - ".$3));
		}
	}
	$s2->{vbox}->pack_start($_,0,0,0) foreach @checks;

	# Handle the relevant events (signals).
	#
	$close ->signal_connect(clicked => sub {$s2->destroy();});


	$remsel ->signal_connect(clicked => sub { confirm_action(1);});
	$corsel ->signal_connect(clicked => sub { confirm_action(2);});
	
	$s2->signal_connect(response => sub {$s2->destroy();});
	$s2->signal_connect(destroy => \&saveBanned);
	$selall->signal_connect(clicked  => sub {
		foreach my $c (@checks) { $c->set_active(1);}
	});
	$selnone->signal_connect(clicked  => sub {
		foreach my $c (@checks) { $c->set_active(0);}
	});

	$s2->show_all();
}

sub loadBanned()
{
	open(my $fh, '<', $Banfile) or return;
	@banned = <$fh>;
	close($fh);
}
sub saveBanned
{
	#write banned files to 'lastfm_corrections.banned' so they don't appear ever again
	return 'no datafile' unless defined $Banfile;

	my $content = '';
	
	return if (scalar@banned == 0);
	
	foreach my $a (@banned) { $content .= $a;}

	open my $fh,'>',$Banfile or warn "Error opening '$Banfile' for writing : $!\n";
	print $fh $content   or warn "Error writing to '$Banfile' : $!\n";
	close $fh;
}

sub confirm_action()
{
	my $type = $_[0];
	my $dialog = Gtk2::Dialog->new ('Confirmation', undef,[qw/modal destroy-with-parent/],'gtk-ok'     => 'ok','gtk-cancel' => 'cancel');
	$dialog->set_position('center-always');
	$dialog->set_border_width(4);

	$dialog->signal_connect(response => sub {$_[0]->destroy;
		if ($_[1] eq 'ok') 
		{ 
			if ($type == 1) {remove_selected();}
			elsif ($type == 2) {correctSelected(0);}
		}
	});
	
    my $label = Gtk2::Label->new();
    my $label2 = Gtk2::Label->new();
    if ($type == 1) 
    { 
    	$label->set_label('Selected corrections will be removed from list.');
    	$label2->set_label('To see them again you have to manually edit banned-file (see README).')
    }
    elsif ($type == 2) 
    { 
    	$label->set_label('Selected corrections will now be applied to filetags.');
    	$label2->set_label('You can\'t undo this operation.')
    	
    }
    $dialog->get_content_area ()->add ($label);
    $dialog->get_content_area ()->add ($label2);
    $dialog->show_all;
}

sub remove_selected
{
	for (my $c=(scalar@checks-1);$c >= 0; $c--)
	{
		if ($checks[$c]->get_active) 
		{ 
			push (@banned,$corrections[$c]); 
			$s2->{vbox}->remove($checks[$c]);
			splice @checks, $c, 1;				
			splice @corrections, $c, 1;
		}
	}
	saveBanned();
	saveCorrections();
}
sub correctSelected()
{
	my $force = $_[0];
	for (my $c=(scalar@checks)-1; $c >= 0; $c--)
	{
		if ($corrections[$c] =~ m/(.+)\t(.+)\t(.+)/)
		{
			my $ID = Songs::FindID($1);
			
			my $oldartist =  Songs::Get(Songs::FindID($1),'artist');
			my $oldtitle =  Songs::Get(Songs::FindID($1),'title');
			
			my $newartist = $2;
			my $newtitle = $3;
			
			my $changetype;
			
			if ($newtitle ne $oldtitle) { $changetype = 1;}
			if ($newartist ne $oldartist) { $changetype = 2;}
			if (($newartist ne $oldartist) and ($newtitle ne $oldtitle)) { $changetype = 3;}
			
			my $trackfilter;
			my @changeTitle;
			my @changeArtist;
			
			if (($changetype == 1) or ($changetype == 3))
			{	
				$trackfilter = Filter->newadd(1,'title:e:'.$oldtitle, 'artist:e:'.$oldartist)->filter;
				if ($::Options{OPT.'titlechange'} eq 'change_all') { foreach my $a (@$trackfilter) { push @changeTitle,$a;} }
			}
			
			if (($changetype == 2) or ($changetype == 3))
			{
				$trackfilter = Filter->newadd(1,'artist:e:'.$oldartist)->filter;
				if ($::Options{OPT.'artistchange'} eq 'change_all') { foreach my $a (@$trackfilter) { push @changeArtist,$a;} }
			}
			
			if ($checks[$c]->get_active) 
			{ 
				if ((scalar@changeTitle == 0) and (scalar@changeArtist == 0))
				{
					Songs::Set($ID, artist=> $newartist, title => $newtitle);
					Log('Corrected tag for '.$oldartist.' - '.$oldtitle.' -> '.$newartist.' - '.$newtitle);	
				}
				else
				{
					print "cT: ".scalar@changeTitle." cA: ".scalar@changeArtist;
					Songs::Set(\@changeTitle, title => $newtitle);
					Songs::Set(\@changeArtist, artist => $newartist);
				}
				
				$s2->{vbox}->remove($checks[$c]);
 				splice @checks, $c, 1;				
 				splice @corrections, $c, 1;
			}				
		}
	}
	saveCorrections();
}
sub askForChange()
{
	
}
1;
