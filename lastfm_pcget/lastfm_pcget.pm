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
#Handle different versions of same song
#Always keep the bigger amount?


package GMB::Plugin::LASTFM_PCGET;
use strict;
use warnings;
use constant
{	CLIENTID => 'gmb', VERSION => '0.1',
	OPT => 'PLUGIN_LASTFM_PCGET_',#used to identify the plugin's options
	APIKEY => 'f39afc8f749e2bde363fc8d3cfd02aae',
};
use Digest::MD5 'md5_hex';
require $::HTTP_module;

my $self=bless {},__PACKAGE__;
my $Log=Gtk2::ListStore->new('Glib::String');
my $waiting;
my $oldID = -1;


sub Start
{
	::Watch($self,PlayingSong=> \&SongChanged);
}
sub Stop
{
	$waiting->abort if ($waiting);
	::UnWatch_all($self);	
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $entry1=::NewPrefEntry(OPT.'USER',_"username :", sizeg1 => $sg1,sizeg2=>$sg2);
	

	my $listcombo= ::NewPrefCombo( OPT.'pcvalues', { always => 'Always set last.fm value', biggest => 'Set bigger amount', smallest => 'Set smaller amount',});
	my $l=Gtk2::Label->new('How to deal with different playcount values: ');

	my $listcombo2= ::NewPrefCombo( OPT.'multiple', { playing => 'Set only playing tracks playcount', split_evenly => 'Split playcount evenly', separate => 'Set every tracks playcount separately', as_one => 'Handle different songs as one',});
	my $l2=Gtk2::Label->new('In case of multiple tracks with same artist and title: ');
	
	$vbox=::Vpack($entry1,[$l,$listcombo],[$l2,$listcombo2]);
	$vbox->add( ::LogView($Log) );
	return $vbox;
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
				
					#always set last.fm value
					if ($pcvalue == 1)
					{
						if ($multiple == 1)	{ if ($1 != $oc) {push(@changeID,$::SongID); push(@changevalue,$1);}}
						elsif ($multiple == 2)	#even split
						{
							if ((scalar@$multifilter == 1) and ($1 != $oc)) {push(@changeID,$::SongID); push(@changevalue,$1);}
							elsif (scalar@$multifilter > 1)
							{
								my $whole = int($1/scalar@$multifilter);
								my $rest = $1%scalar@$multifilter;

								foreach my $b (@$multifilter)
								{
									push(@changeID,$b); 
									push(@changevalue,($whole+$rest));
									if ($rest > 0) { $rest--; }
								}
							}
						}
						elsif (($multiple == 3) or ($multiple == 4))#separate or as_one
						{
							foreach my $b (@$multifilter){push(@changeID,$b);push(@changevalue,$1);	}
						}
					}
					else #set biggest/smallest value
					{
						my $modifier = 1;#smallest
						$modifier = -1 if ($pcvalue == 2);#biggest
						
						if ($multiple == 1)#current only
						{
							if ($modifier*($oc-$1) < 0) 
							{ 
								foreach my $b (@$multifilter){push(@changeID,$b);push(@changevalue,$oc);}							
							}
							else {foreach my $b (@$multifilter){push(@changeID,$b);push(@changevalue,$1);}}
						}
						elsif ($multiple == 2)#split even
						{
							my $whole;
							my $rest;
							if ($modifier*($oc-$1) < 0) 
							{
								$whole = int($oc/scalar@$multifilter);
								$rest = $oc%scalar@$multifilter;
							}
							else
							{
								$whole = int($1/scalar@$multifilter);
								$rest = $1%scalar@$multifilter;
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
								if ($modifier*($curoc-$1) > 0)
								{
									#only change if last.fm has wanted value 
									push(@changeID,$b); 
									push(@changevalue,$1);
								}
							}
						}
						elsif ($multiple == 4)#handle as one
						{
							my $curoc;
							if ($modifier*($oc-$1) < 0)	{$curoc = $oc;}
							else {$curoc = $1; }

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
				Log "Set playcount to ".$changevalue[$c]." for ".Songs::Get($changeID[$c],'artist')." - ".Songs::Get($changeID[$c],'album')." - ".Songs::Get($changeID[$c],'title');
			}
		}
		else { Log("Nothing to change for ".$artist." - ".$album." - ".$title) }
	};
	my $waiting=Simple_http::get_with_cb(cb => $cb,url => $url,post => '');
}

1;