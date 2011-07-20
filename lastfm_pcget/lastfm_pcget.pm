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
};
use Digest::MD5 'md5_hex';
require $::HTTP_module;

our $ignore_current_song;

my $self=bless {},__PACKAGE__;
my ($Serrors,$Stop);
my $Log=Gtk2::ListStore->new('Glib::String');
my $syncing=0;
my $sync_timeout;

sub Start
{	::Watch($self,PlayingSong=> \&SongChanged);
	$Serrors=$Stop=undef;
}
sub Stop
{
	
}

sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $entry1=::NewPrefEntry(OPT.'USER',_"username :", cb => \&userpass_changed, sizeg1 => $sg1,sizeg2=>$sg2);
	my $entry2=::NewPrefEntry(OPT.'PASS',_"password :", cb => \&userpass_changed, sizeg1 => $sg1,sizeg2=>$sg2, hide => 1);
	my $entry3=::NewPrefEntry(OPT.'APIKEY',_"API Key :", sizeg1 => $sg1,sizeg2=>$sg2);
	
	my @list = ( 'Always set last.fm value', 'Set bigger amount', 'Set smaller amount');
	my $listcombo= ::NewPrefCombo( OPT.'pcvalue', \@list);
	my $l=Gtk2::Label->new('How to deal with different playcount values: ');

	my @list2 = ( 'Set only playing tracks playcount', 'Split playcount evenly', 'Set every tracks playcount separately', 'Handle different songs as one');
	my $listcombo2= ::NewPrefCombo( OPT.'multipletrack', \@list2);
	my $l2=Gtk2::Label->new('In case of multiple tracks with same artist and title: ');
	
	
	$vbox=::Vpack($entry1,$entry2,$entry3,[$l,$listcombo],[$l2,$listcombo2]);
	$vbox->add( ::LogView($Log) );
	return $vbox;
}

sub SongChanged
{	
	Sync();
}


sub Log
{	my $text=$_[0];
	$Log->set( $Log->prepend,0, localtime().'  '.$text );
	warn "$text\n" if $::debug;
	if (my $iter=$Log->iter_nth_child(undef,50)) { $Log->remove($iter); }
}

sub Sync_Awake()
{
	$syncing = 0;
	$sync_timeout=undef;
}
sub Sync()
{
	#Send(\&response_cb,'http://post.audioscrobbler.com/?hs=true&p=1.2&c='.CLIENTID.'&v='.VERSION."&u=$user&t=$time&a=$auth");
	#my ($got_cb,$url,$post)=@_;

	return if ($syncing == 1);

	$syncing = 1;

	my $user=$::Options{OPT.'USER'};
	my $key=$::Options{OPT.'APIKEY'};
	
	if (($user eq '') or ($key eq '')) { return;}

	my $artist = Songs::GetTagValue($::SongID,'artist');
	my $title = Songs::GetTagValue($::SongID,'title');
	my $oc = Songs::GetTagValue($::SongID,'playcount');

	my $url = 'http://ws.audioscrobbler.com/2.0/?method=track.getinfo&username='.$user.'&api_key='.$key.'&artist='.::url_escapeall($artist).'&track='.::url_escapeall($title);
	my $upc = '<userplaycount>';
	my $upc2 = '</userplaycount>';
	my $foundupc = 0;

	my $multifilter=Filter->newadd(1,'title:e:'.$title, 'artist:e:'.$artist)->filter;
	my $act=0;
	my $type;
	my $total = 0;
	
	if ($::Options{OPT.'multipletrack'} eq 'Set only playing tracks playcount') { $type = 1; }
	elsif ($::Options{OPT.'multipletrack'} eq 'Split playcount evenly') { $type = 2; }
	elsif ($::Options{OPT.'multipletrack'} eq 'Handle different songs as one') { $type = 4; }
	else { $type = 3; } #max everything
	
	my $cb=sub
	{	
		my @r=(defined $_[0])? split "\012",$_[0] : ();
		foreach my $a (@r) 
		{
			if ( $a =~ m/$upc(\d+)$upc2/)
			{
					$foundupc = 1;
					
					if ($::Options{OPT.'pcvalue'} eq 'Always set last.fm value'){$act = 1;}
					elsif ($::Options{OPT.'pcvalue'} eq 'Set bigger amount') 
					{
						foreach my $b (@$multifilter)
						{
							$oc = Songs::GetTagValue($b,'playcount');
							if ($oc < $1){$act = 2;	}
						}
					}
					elsif ($::Options{OPT.'pcvalue'} eq 'Set smaller amount') 
					{
						foreach my $b (@$multifilter)
						{
							$oc = Songs::GetTagValue($b,'playcount');
							if ($oc > $1){$act = 3;	}
						}
					}
					
					if (($act != 0) and (scalar@$multifilter == 1))	{ Songs::SetTagValue($::SongID,'playcount',$1); Log("Set playcount for ".$artist." - ".$title." (".$1.")");}
					elsif (($act == 1) and ($type==1)){Songs::SetTagValue($::SongID,'playcount',$1); Log("Set playcount for ".$artist." - ".$title." (".$1.")");}
					elsif (($act == 1) and ($type==2)){$total = $1;}
					elsif (($act == 1) and ($type==3))
					{ 
						foreach my $c (@$multifilter) 
						{	
							my $album = Songs::GetTagValue($c,'album');
							Songs::SetTagValue($c,'playcount',$1);
							Log("Set playcount for ".$artist." - ".$album." - ".$title." (".$1.")");
						}
					}
					elsif (($act == 1) and ($type==4))
					{ 
						foreach my $c (@$multifilter) 
						{	
							my $album = Songs::GetTagValue($c,'album');
							Songs::SetTagValue($c,'playcount',$1);
							Log("Set playcount for ".$artist." - ".$album." - ".$title." (".$1.")");
						}
					}
					elsif (($act == 2) and ($type==1)){Songs::SetTagValue($::SongID,'playcount',$1); Log("Set playcount for ".$artist." - ".$title." (".$1.")");}
					elsif (($act == 2) and ($type==2))
					{ 
						#choose biggest and multiply with scalar@$multifilter
						my $biggest = $1; 
						foreach my $c (@$multifilter){ if (Songs::GetTagValue($c,'playcount') > $biggest) {$biggest = Songs::GetTagValue($c,'playcount')}}
						$total = $biggest*scalar@$multifilter;
					}
					elsif (($act == 2) and ($type==3))
					{ 
						foreach my $c (@$multifilter) 
						{ 
							if (Songs::GetTagValue($c,'playcount') < $1) 
							{
								my $album = Songs::GetTagValue($c,'album');
								Songs::SetTagValue($c,'playcount',$1);
								Log("Set playcount for ".$artist." - ".$album." - ".$title." (".$1.")");
							}
						}
					}
					elsif (($act == 2) and ($type==4))
					{ 
						#calculate average
						my $sum = 0; 
						foreach my $c (@$multifilter){ $sum += Songs::GetTagValue($c,'playcount'); }
						my $average = int(($sum/scalar@$multifilter)+0.5);
						Log("Calculating value with average on multiple tracks: ".$average." = ".$sum."/".scalar@$multifilter);
						foreach my $d (@$multifilter)
						 {
							my $album = Songs::GetTagValue($d,'album');						 	
							if ($average < $1){Songs::SetTagValue($d,'playcount',$1); Log("Set playcount for ".$artist." - ".$album." - ".$title." (".$1.")");}
							else {Songs::SetTagValue($d,'playcount',$average); Log("Set playcount for ".$artist." - ".$album." - ".$title." (".$average.")");}
						}
						
					}
					elsif (($act == 3) and ($type==1)){Songs::SetTagValue($::SongID,'playcount',$1); Log("Set playcount for ".$artist." - ".$title." (".$1.")");}
					elsif (($act == 3) and ($type==2))
					{ 
						#choose smallest and multiply with scalar@$multifilter
						my $smallest = $1; 
						foreach my $c (@$multifilter){ if (Songs::GetTagValue($c,'playcount') < $smallest) {$smallest = Songs::GetTagValue($c,'playcount')}}
						$total = $smallest*scalar@$multifilter;
					}
					elsif (($act == 3) and ($type==3))
					{ 
						foreach my $c (@$multifilter) 
						{ 
							if (Songs::GetTagValue($c,'playcount') > $1) 
							{
								my $album = Songs::GetTagValue($c,'album');
								Songs::SetTagValue($c,'playcount',$1);
								Log("Set playcount for ".$artist." - ".$album." - ".$title." (".$1.")");
							}
						}
					}
					elsif (($act == 3) and ($type==4))
					{ 
						#calculate average
						my $sum = 0; 
						foreach my $c (@$multifilter){ $sum += Songs::GetTagValue($c,'playcount'); }
						my $average = int(($sum/scalar@$multifilter)+0.5);
						Log("Calculating value with average on multiple tracks: ".$average." = ".$sum."/".scalar@$multifilter);
						foreach my $d (@$multifilter)
						 {
							my $album = Songs::GetTagValue($d,'album');						 	
							if ($average > $1){Songs::SetTagValue($d,'playcount',$1); Log("Set playcount for ".$artist." - ".$album." - ".$title." (".$1.")");}
							else {Songs::SetTagValue($d,'playcount',$average); Log("Set playcount for ".$artist." - ".$album." - ".$title." (".$average.")");}
						}
						
					}
					else { Log("No change in playcount for ".$artist." - ".$title." (".$oc.")");}
				
					#then handle 'split' if necessary
					
					if ($total > 0)
					{
						my $whole = int($total/scalar@$multifilter);
						my $rest = $total%scalar@$multifilter;
						 Log("Splitting value evenly on multiple tracks: ".$total." = ".scalar@$multifilter."*".$whole." + ".$rest);
						
						foreach my $d (@$multifilter)
						{
							my $album = Songs::GetTagValue($d,'album');
							Log("Split playcount for ".$artist." - ".$album." - ".$title." (".($whole+$rest).")");
							Songs::SetTagValue($d,'playcount',($whole+$rest));
							if ($rest > 0) { $rest--; }
						}
					}

			} 
		}
		if ($foundupc == 0) {Log('No previous playcount found for '.$artist.' - '.$title);}
	};
	my $thing=Simple_http::get_with_cb(cb => $cb,url => $url,post => '');
	$sync_timeout = Glib::Timeout->add(3000,\&Sync_Awake);
}

1;
