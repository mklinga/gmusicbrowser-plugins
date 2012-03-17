# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# History/Stats: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
#
# This file is a plugin to Gmusicbrowser.
# It is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

# TODO:
# - time-based (as in weekly/monthly etc.) stats (only for playcount) 
# - Weekly/Monthly topNN, weeksinlist/last week position etc.
# - histogram for stats
# - recent albums / album treshold
# - do overview setting: track/album
#
# BUGS:
# - [ochosi:] pressing the sort-button in history/stats crashes gmb ?
#

=gmbplugin HISTORYSTATS
name	History/Stats
title	History/Stats - plugin
version 0.01
desc	Show playhistory and statistics in layout
=cut

package GMB::Plugin::HISTORYSTATS;

use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_HISTORYSTATS_',
};

use utf8;
require $::HTTP_module;
use Gtk2::Gdk::Keysyms;
use base 'Gtk2::Box';
use base 'Gtk2::Dialog';

::SetDefaultOptions(OPT,RequirePlayConditions => 1, HistoryLimitMode => 'days', AmountOfHistoryItems => 3, 
	AmountOfStatItems => 50, UseHistoryFilter => 0, TotalPlayTime => 0, 
	TotalPlayTracks => 0, ShowArtistForAlbumsAndTracks => 1, HistoryTimeFormat => '%d.%m.%y %H:%M:%S',
	HistoryItemFormat => '%a - %l - %t',FilterOnDblClick => 0, LogHistoryToFile => 0, SetFilterOnLeftClick => 1,
	PerAlbumInsteadOfTrack => 0, ShowStatNumbers => 1, AddCurrentToStatList => 1, OverviewTopMode => 'playcount:sum',
	OverViewTopAmount => 5, CoverSize => 60, StatisticsTypeCombo => 'Artists',
	StatisticsSortCombo => 'Playcount (Average)');

my %sites =
(
	statistics => ['',_"Statistics",_"Show statistics"],
	overview => ['',_"Overview",_"Overview of statistics"],
	history => ['',_"History",_"Show playhistory"]
);

my %StatTypes = (
 #album_artists => { label => 'Album Artists', field => 'album_artist'}, 
 artists => { label => 'Artists', field => 'artist'}, 
 albums => { label => 'Albums', field => 'album'}, 
 labels => { label => 'Labels', field => 'label'}, 
 genres => { label => 'Genres', field => 'genre'}, 
 year => { label => 'Years', field => 'year'}, 
 titles => { label => 'Tracks', field => 'title'} 
);

my %SortTypes = (
 playcount => { label => 'Playcount (Average)', typecode => 'playcount', suffix => ':average'}, 
 playcount_total => { label => 'Playcount (Total)', typecode => 'playcount', suffix => ':sum'}, 
 rating => { label => 'Rating', typecode => 'rating', suffix => ':average'},
 timecount_total => { label => 'Time played', typecode => 'playedlength', suffix => ':sum'}, 
);

my %statupdatemodes = ( 
	songchange => 'On songchange', 
	albumchange => 'On albumchange', 
	initial => 'Only initially'
);

my %OverviewTopheads = (
	artist => {label => 'Top Artists', enabled => 1},
	album => {label => 'Top Albums', enabled => 0},
	title => {label => 'Top Tracks', enabled => 0},
	genre => {label => 'Top Genres', enabled => 0}
);

my $statswidget =
{	class		=> __PACKAGE__,
	tabicon		=> 'plugin-historystats',
	tabtitle	=> _"History/Stats",
	#schange		=> \&SongChanged,
	#group		=> 'Play',
	autoadd_type	=> 'context page text',
};

my $LogFile = $::HomeDir.'playhistory.log';
my %AdditionalData; #holds additional playcounts, key is 'pt' + (last playcount of track), value is array
my %HistoryHash = ( needupdate => 1);# last play of every track, key = 'pt'.Playtime
my %sourcehash;
my $lastID = -1; 
my %lastAdded = ( ID => -1, playtime => -1);
my $lastPlaytime;
my %globalstats;

sub Start {
	Layout::RegisterWidget(HistoryStats => $statswidget);
	if (not defined $::Options{OPT.'StatisticsStartTime'}) {
		$::Options{OPT.'StatisticsStartTime'} = time;
	}
	$globalstats{starttime} = $::Options{OPT.'StatisticsStartTime'}; 
	$globalstats{playtime} = $::Options{OPT.'TotalPlayTime'};
	$globalstats{playtrack} = $::Options{OPT.'TotalPlayTracks'};
	
	for (keys %OverviewTopheads) { 
		if (defined $::Options{OPT.'OVTH'.$_}) {$OverviewTopheads{$_}->{enabled} = $::Options{OPT.'OVTH'.$_};}
		else {$::Options{OPT.'OVTH'.$_} = $OverviewTopheads{$_}->{enabled};}
	}
}

sub Stop {
	Layout::RegisterWidget(HistoryStats => undef);
}

sub prefbox 
{
	
	my @frame=(Gtk2::Frame->new(" General options "),Gtk2::Frame->new(" History "),Gtk2::Frame->new(" Overview "),Gtk2::Frame->new(" Statistics "));
	
	#General
	my $gAmount1 = ::NewPrefSpinButton(OPT.'CoverSize',50,200, step=>10, page=>25, text =>_("Album cover size"));	

	# History
	my $hCheck1 = ::NewPrefCheckButton(OPT.'RequirePlayConditions','Add only songs that count as played', tip => 'You can set treshold for these conditions in Preferences->Misc', cb => sub{  $HistoryHash{needupdate} = 1;});
	my $hCheck2 = ::NewPrefCheckButton(OPT.'UseHistoryFilter','Show history only from selected filter', cb => sub{ $HistoryHash{needupdate} = 1;});
	my $hCheck3 = ::NewPrefCheckButton(OPT.'LogHistoryToFile','Log playhistory to file');
	my $hAmount = ::NewPrefSpinButton(OPT.'AmountOfHistoryItems',1,1000, step=>1, page=>10, text =>_("Limit history to "), cb => sub{  $HistoryHash{needupdate} = 1;});
	my @historylimits = ('items','days');
	my $hCombo = ::NewPrefCombo(OPT.'HistoryLimitMode',\@historylimits, cb => sub{ $HistoryHash{needupdate} = 1;});
	my $hEntry1 = ::NewPrefEntry(OPT.'HistoryTimeFormat','Format for time: ', tip => "Available fields are: \%d, \%m, \%y, \%h (12h), \%H (24h), \%M, \%S \%p (am/pm-indicator)");
	my $hEntry2 = ::NewPrefEntry(OPT.'HistoryItemFormat','Format for tracks: ', tip => "You can use all fields from gmusicbrowsers syntax (see http://gmusicbrowser.org/layout_doc.html)", cb => sub { $HistoryHash{needrecreate} = 1;});

	# Overview
	my $oAmount = ::NewPrefSpinButton(OPT.'OverViewTopAmount',1,20, step=>1, page=>2, text =>_("Number of top-items in Overview: "));
	my $oLabel1 = Gtk2::Label->new('Show toplists for (changing requires restart of plugin):');
	$oLabel1->set_alignment(0,0.5);
	my $oCheck1 = ::NewPrefCheckButton(OPT.'OVTHartist','Artists');
	my $oCheck2 = ::NewPrefCheckButton(OPT.'OVTHalbum','Albums');
	my $oCheck3 = ::NewPrefCheckButton(OPT.'OVTHtitle','Tracks');
	my $oCheck4 = ::NewPrefCheckButton(OPT.'OVTHgenre','Genres');
	
	# Statistics
	my $sAmount = ::NewPrefSpinButton(OPT.'AmountOfStatItems',10,10000, step=>5, page=>50, text =>_("Limit amount of shown items to "));
	my $sCheck1 = ::NewPrefCheckButton(OPT.'ShowArtistForAlbumsAndTracks','Show artist for albums and tracks in list');
	my $sCheck2 = ::NewPrefCheckButton(OPT.'SetFilterOnLeftClick','Show items selected with left-click');
	my $sCheck3 = ::NewPrefCheckButton(OPT.'FilterOnDblClick','Set Filter when playing items with double-click', tip => 'This option doesn\'t apply to single tracks');
	my $sCheck4 = ::NewPrefCheckButton(OPT.'PerAlbumInsteadOfTrack','Calculate groupstats per album instead of per track');
	my $sCheck5 = ::NewPrefCheckButton(OPT.'ShowStatNumbers','Show numbers in list');
	my $sCheck6 = ::NewPrefCheckButton(OPT.'AddCurrentToStatList','Always show currently playing item in list');
	my @sum = (values %statupdatemodes);
	my $sCombo = ::NewPrefCombo(OPT.'StatViewUpdateMode',\@sum, text => 'Update Statistics: ');
	
	my @vbox = ( 
		::Vpack($gAmount1), 
		::Vpack([$hCheck1,$hCheck2],$hCheck3,[$hAmount,$hCombo],$hEntry1,$hEntry2), 
		::Vpack($oLabel1,[$oCheck1,$oCheck2,$oCheck3,$oCheck4],[$oAmount]),
		::Vpack([$sCheck1,$sCheck4],[$sCheck2,$sCheck3],[$sCheck5,$sCheck6],$sAmount,[$sCombo]) 
	);
	
	$frame[$_]->add($vbox[$_]) for (0..$#frame);
		
	return ::Vpack($frame[0],$frame[1],$frame[2],$frame[3]);
}

sub new 
{
	my ($class,$options)=@_;
	my $self = bless Gtk2::VBox->new(0,0), $class;
	my $group= $options->{group};
	my $fontsize=$self->style->font_desc;
	$self->{fontsize} = $fontsize->get_size / Gtk2::Pango->scale;
	$self->{site} = 'history';
	$self->signal_connect(map => \&SongChanged);

	my ($Hvbox, $Hstore,$Hstore_albums) = CreateHistorySite($self);
	my ($Ovbox,$Ostore_toplist,$Ostore) = CreateOverviewSite($self,$options);	
	my ($Streeview,$Sstore,$Sinvert,$stat_hbox1,$iw,@combos,@labels) = CreateStatisticsSite($self);
	my $toolbar = CreateToolbar($self,$options);

	$self->{hstore}=$Hstore;
	$self->{hstore_albums}=$Hstore_albums;
	$self->{ostore_recent}=$Ostore;
	$self->{ostore_toplist}=$Ostore_toplist;
	$self->{sstore}=$Sstore;
	$self->{butinvert} = $Sinvert;
	$self->{stattypecombo} = $combos[1];
	$self->{Ovbox} = $Ovbox;

	my $infobox = Gtk2::HBox->new; 	$infobox->set_spacing(0);
	my $site_overview = $Ovbox;
	my $site_history= $Hvbox;
	my $sh = Gtk2::ScrolledWindow->new;
	$sh->add($Streeview);
	$sh->set_shadow_type('none');
	$sh->set_policy('automatic','automatic');

	my $site_statistics = Gtk2::VBox->new(); 
	$site_statistics->pack_start($stat_hbox1,0,0,0);
	$site_statistics->pack_start($sh,1,1,0);

	$infobox->pack_start($site_history,1,1,0);
	$infobox->pack_start($site_overview,1,1,0);
	$infobox->pack_start($site_statistics,1,1,0);

	#show everything from hidden pages
	$Streeview->show; $stat_hbox1->show; $sh->show;
	$_->show for (@combos); $_->show for (@labels);
	$Sinvert->show; $iw->show;
	
	#starting site is always 'history'
	$site_overview->set_no_show_all(1);
	$site_statistics->set_no_show_all(1);

	$self->{site_overview} = $site_overview; 
	$self->{site_history} = $site_history; 
	$self->{site_statistics} = $site_statistics;

	$self->pack_start($toolbar,0,0,0);
	$self->pack_start($infobox,1,1,0);
	
	$self->{needsupdate} = 1;

	$self->signal_connect(destroy => \&DestroyCb);
	::Watch($self, PlayingSong => \&SongChanged);
	::Watch($self, Played => \&SongPlayed);
	::Watch($self, Filter => sub 
		{
			my $force;
			$force = 1 unless (($self->{site} eq 'history') and (!$::Options{OPT.'UseHistoryFilter'}));
			SongChanged($self,$force);
			$HistoryHash{needupdate} = 1;
		});
	
	UpdateSite($self,$self->{site});
	return $self;
}

sub CreateHistorySite
{
	## TreeView for history
	my $Hstore=Gtk2::ListStore->new('Glib::String','Glib::String','Glib::UInt','Glib::String');
	my $Htreeview=Gtk2::TreeView->new($Hstore);
	my $Hplaytime=Gtk2::TreeViewColumn->new_with_attributes( "Playtime",Gtk2::CellRendererText->new,text => 0);
	$Hplaytime->set_sort_column_id(0);
	$Hplaytime->set_resizable(1);
	$Hplaytime->set_alignment(0);
	$Hplaytime->set_min_width(10);
	my $Htrack=Gtk2::TreeViewColumn->new_with_attributes( _"Track",Gtk2::CellRendererText->new,text=>1);
	$Htrack->set_sort_column_id(1);
	$Htrack->set_expand(1);
	$Htrack->set_resizable(1);
	$Htreeview->append_column($Hplaytime);
	$Htreeview->append_column($Htrack);

	$Htreeview->get_selection->set_mode('multiple');
	$Htreeview->set_rules_hint(1);
	$Htreeview->signal_connect(button_press_event => \&HTVContext);
	$Htreeview->{store}=$Hstore;

	my $Hstore_albums=Gtk2::ListStore->new('Gtk2::Gdk::Pixbuf','Glib::String','Glib::UInt','Glib::String');
	my $Htreeview_albums=Gtk2::TreeView->new($Hstore_albums);
	my $Hpic=Gtk2::TreeViewColumn->new_with_attributes( "",Gtk2::CellRendererPixbuf->new,pixbuf => 0);
	$Hpic->set_sort_column_id(0);
	$Hpic->set_resizable(1);
	$Hpic->set_alignment(0);
	$Hpic->set_min_width(10);
	my $Halbum=Gtk2::TreeViewColumn->new_with_attributes( _"Album",Gtk2::CellRendererText->new,text=>1);
	$Halbum->set_sort_column_id(1);
	$Halbum->set_expand(1);
	$Halbum->set_resizable(1);
	$Htreeview_albums->append_column($Hpic);
	$Htreeview_albums->append_column($Halbum);
	$Htreeview_albums->get_selection->set_mode('multiple');
	$Htreeview_albums->set_rules_hint(1);
	$Htreeview_albums->signal_connect(button_press_event => \&HTVContext);
	$Htreeview_albums->{store}=$Hstore_albums;

	my $vbox = Gtk2::VBox->new;
	my $sh = Gtk2::ScrolledWindow->new;	
	$sh->add($Htreeview);
	$sh->set_shadow_type('none');
	$sh->set_policy('automatic','automatic');

	my $sh2 = Gtk2::ScrolledWindow->new;	
	$sh2->add($Htreeview_albums);
	$sh2->set_shadow_type('none');
	$sh2->set_policy('automatic','automatic');
	
	$vbox->pack_start($sh,1,1,0);
	$vbox->pack_start($sh2,1,1,0);

	return ($vbox,$Hstore,$Hstore_albums);	
}

sub CreateOverviewSite
{
	my ($self,$options) = @_;
	my $vbox = Gtk2::VBox->new;

	# top-lists
	my @topheads;
	for (keys %OverviewTopheads) { push @topheads, $OverviewTopheads{$_}->{label} if $OverviewTopheads{$_}->{enabled};}
	
	my @Ostore_toplists; my @Otoptreeviews;
	
	for (0..$#topheads)
	{
		push @Ostore_toplists, Gtk2::ListStore->new('Glib::String','Glib::String','Glib::UInt','Glib::String');#label, pc, ID, field
		push @Otoptreeviews, Gtk2::TreeView->new($Ostore_toplists[$_]);
		my $Oc=Gtk2::TreeViewColumn->new_with_attributes( $topheads[$_],Gtk2::CellRendererText->new,text => 0);
		$Oc->set_expand(1);
		$Otoptreeviews[$_]->append_column($Oc);
		my $render = Gtk2::CellRendererText->new;
		$render->set_alignment(1,.5);
		my $Opc=Gtk2::TreeViewColumn->new_with_attributes( "Playcount",$render,text => 1);
		$Opc->set_expand(0);
		$Otoptreeviews[$_]->append_column($Opc);

		$Otoptreeviews[$_]->get_selection->set_mode('single');
		$Otoptreeviews[$_]->set_rules_hint(1);
		$Otoptreeviews[$_]->set_headers_visible(1);
		$Otoptreeviews[$_]->signal_connect(button_press_event => \&HTVContext);
		$Otoptreeviews[$_]->{store}=$Ostore_toplists[$_];
		$Otoptreeviews[$_]->show;
		
		my $sw = Gtk2::ScrolledWindow->new;
		$sw->add($Otoptreeviews[$_]);
		$sw->set_shadow_type('none');
		$sw->set_policy('automatic','automatic');
		$sw->show;
		$vbox->pack_start($sw,1,1,0);
	}

	#treeview for top40
	my $Ostore; my $Otreeview;
	my @coverlabels = ('Recently Added Albums','Recently Played Albums');
	$Ostore=Gtk2::ListStore->new('Gtk2::Gdk::Pixbuf','Glib::String','Gtk2::Gdk::Pixbuf','Glib::String','Glib::UInt','Glib::UInt');
	$Otreeview=Gtk2::TreeView->new($Ostore);
	for (0..1)
	{
		my $Opic=Gtk2::TreeViewColumn->new_with_attributes( "",Gtk2::CellRendererPixbuf->new,pixbuf => (2*$_));
		$Opic->set_sort_column_id(2*$_);
		$Opic->set_fixed_width($::Options{OPT.'CoverSize'});
		$Opic->set_min_width($::Options{OPT.'CoverSize'});
		my $Otext=Gtk2::TreeViewColumn->new_with_attributes( $coverlabels[$_],Gtk2::CellRendererText->new,text => (1+2*$_));
		$Otext->set_sort_column_id(1+2*$_);
		$Otext->set_expand(1);
		
		$Otreeview->append_column($Opic);
		$Otreeview->append_column($Otext);
	}

	$Otreeview->get_selection->set_mode('none');
	$Otreeview->set_rules_hint(1);
	$Otreeview->set_headers_visible(1);
#	$Otreeview->signal_connect(button_press_event => \&HTVContext);
	$Otreeview->{store}=$Ostore;

	my $sh = Gtk2::ScrolledWindow->new;
	$sh->add($Otreeview);
	$sh->set_shadow_type('none');
	$sh->set_policy('automatic','automatic');
	$sh->show;
	$vbox->pack_start($sh,1,1,0);
		
	$Otreeview->show;

	# statuslabel in the bottom
	my $ago = (time-$globalstats{starttime})/86400;
	my $text = "Since ".FormatRealtime($globalstats{starttime},'%d.%m.%y');
	if ($ago)
	{
		$text .= " you have played a total of ".$globalstats{playtrack}." tracks.";
		$text .= " That's about ".int(0.5+($globalstats{playtrack}/$ago))." per day.";
	}	

	
	my $totalstatus_label = Gtk2::Label->new($text);
	$totalstatus_label->set_alignment(0,0); $totalstatus_label->show;
	$vbox->pack_end($totalstatus_label,0,0,0);
	
	return ($vbox,\@Ostore_toplists,$Ostore);
}
sub CreateStatisticsSite
{
	my $self = shift;
	
	## Treeview and little else for statistics
	my $stat_hbox1 = Gtk2::HBox->new;
	my @labels = (Gtk2::Label->new('Show'),Gtk2::Label->new('by'));
	my @lists = (undef,undef,undef); 
	push @{$lists[0]}, $StatTypes{$_}->{label} for (sort keys %StatTypes);
	push @{$lists[1]}, $SortTypes{$_}->{label} for (sort keys %SortTypes);

	my @combos; my @coptname = (OPT.'StatisticsTypeCombo',OPT.'StatisticsSortCombo');
	for (0..1) {
		$combos[$_] = ::NewPrefCombo($coptname[$_],$lists[$_]);
		$combos[$_]->signal_connect(changed => sub {Updatestatistics($self);});
		$stat_hbox1->pack_start($labels[$_],0,0,1);
		$stat_hbox1->pack_start($combos[$_],1,1,1);
	}
	
	#buttons for avg & inv
	my $Sinvert = Gtk2::ToggleButton->new();
	my $iw=Gtk2::Image->new_from_stock('gtk-sort-descending','menu');
	$Sinvert->add($iw);
	$Sinvert->set_tooltip_text('Invert sorting order');
	$Sinvert->signal_connect(toggled => sub {Updatestatistics($self);});

	$stat_hbox1->pack_start($Sinvert,0,0,0);

	# Treeview for statistics
	my $Sstore=Gtk2::ListStore->new('Glib::String','Glib::String','Glib::UInt','Glib::String');
	my $Streeview=Gtk2::TreeView->new($Sstore);

	my $Sitemrenderer=Gtk2::CellRendererText->new;
	my $Sitem=Gtk2::TreeViewColumn->new_with_attributes( "Item",$Sitemrenderer,markup => 0);
	$Sitem->set_cell_data_func($Sitemrenderer, sub 
	{ 
		my ($column, $cell, $model, $iter, $func_data) = @_; 
		my $raw = $model->get($iter,0);
		my $gid = $model->get($iter,2);
		my $field = $model->get($iter,3);
		if (($::Options{OPT.'ShowArtistForAlbumsAndTracks'}) and ($field =~ /album|title/)) {
			my $arti; my $num = ''; 
			if ($field eq 'album') { my $ag = AA::Get('album_artist:gid','album',$gid); $arti = Songs::Gid_to_Display('album_artist',$$ag[0]); } 
			else { $arti = Songs::Get($gid,'artist'); }
			if ($raw =~ /^(\d+\. )(.+)/) { $num = $1; $raw = $2;}
			$arti = ::PangoEsc($arti);  
			$raw = $num.$raw.'<small>  by  '.$arti.'</small>';
		}
		
		if ($::SongID){
			my $nowplaying = ($field eq 'title')? $::SongID : Songs::Get_gid($::SongID,$field);
			if (ref($nowplaying) eq 'ARRAY') { for (@$nowplaying) {if ($_ == $gid) {$raw = '<b>'.$raw.'</b>';}}}
			elsif ($nowplaying == $gid) { $raw = '<b>'.$raw.'</b>';}
		}

		$cell->set( markup => $raw ); 
	}, undef);
	
	$Sitem->set_sort_column_id(0);
	$Sitem->set_expand(1);
	$Sitem->set_resizable(1);
	$Sitem->set_clickable(::FALSE);
	$Sitem->set_sort_indicator(::FALSE);
	$Streeview->append_column($Sitem);

	my $Svaluerenderer=Gtk2::CellRendererText->new;
	my $Svalue=Gtk2::TreeViewColumn->new_with_attributes( "Value",$Svaluerenderer,text => 1);
	$Svalue->set_cell_data_func($Svaluerenderer, sub 
	{ 
		my ($column, $cell, $model, $iter, $func_data) = @_; 
		my $raw = $model->get($iter,1);
		$cell->set( text => $raw ); 
	}, undef);
	$Svalue->set_sort_column_id(1);
	$Svalue->set_alignment(0);
	$Svalue->set_resizable(1);
	$Svalue->set_min_width(10);
	$Svalue->set_clickable(::FALSE);
	$Svalue->set_sort_indicator(::FALSE);
	$Streeview->append_column($Svalue);
	$Streeview->set_rules_hint(1);
	my $Sselection = $Streeview->get_selection;
	$Sselection->set_mode('multiple');
	$Sselection->signal_connect(changed => \&STVChanged);
	
	$Streeview->signal_connect(button_press_event => \&STVContextPress);
	$Streeview->{store}=$Sstore;
	
	return ($Streeview,$Sstore,$Sinvert,$stat_hbox1,$iw,@combos,@labels);	
}

sub CreateToolbar
{
	my ($self,$options) = @_;
	
	## Toolbar buttons on top of widget
	my $toolbar=Gtk2::Toolbar->new;
	$toolbar->set_style( $options->{ToolbarStyle}||'both-horiz' );
	$toolbar->set_icon_size( $options->{ToolbarSize}||'small-toolbar' );
	my $radiogroup; my $menugroup;
	foreach my $key (sort keys %sites)
	{	my $item = $sites{$key}[1];
		$item = Gtk2::RadioButton->new($radiogroup,$item);
		$item->{key} = $key;
		$item -> set_mode(0); # display as togglebutton
		$item -> set_relief("none");
		$item -> set_tooltip_text($sites{$key}[2]);
		$item->set_active( $key eq $self->{site} );
		$item->signal_connect(toggled => sub { my $self=::find_ancestor($_[0],__PACKAGE__); ToggleCb($self,$item); } );
		$radiogroup = $item -> get_group;
		my $toolitem=Gtk2::ToolItem->new;
		$toolitem->add( $item );
		$toolitem->set_expand(1);
		$toolbar->insert($toolitem,-1);

	}
	
	return $toolbar;
}

sub DestroyCb
{
	return 1;
}

sub ToggleCb
{	
	my ($self, $togglebutton) = @_;
	return unless ($self->{site} ne $togglebutton->{key});

	$self->{needsupdate} = 1;
	
	if ($togglebutton -> get_active) {
		for my $key (keys %sites) {
			if ($key eq $togglebutton->{key}) {$self->{'site_'.$key}->show;}
			else {$self->{'site_'.$key}->hide;}
		}
		$self->{site} = $togglebutton->{key};
	}
	UpdateSite($self,$togglebutton->{key});
}

sub UpdateSite
{
	my ($self,$site,$force) = @_;
	return unless ((($self->{needsupdate}) or ($force)) and (defined $site));

	eval('Update'.$site.'($self);');
	if ($@) { warn "Bad eval in Historystats::UpdateSite()! Site: ".$site.", ERROR: ".$@;}

	$self->{needsupdate} = 0;

	return 1;
}

sub Updatestatistics
{
	my $self = shift;

	my ($field) = grep { $StatTypes{$_}->{label} eq $::Options{OPT.'StatisticsTypeCombo'}} keys %StatTypes;
	my ($sorttype) = grep { $SortTypes{$_}->{label} eq $::Options{OPT.'StatisticsSortCombo'}} keys %SortTypes;

	return unless (($field) and ($sorttype));

	my $suffix = $SortTypes{$sorttype}->{suffix};
	$field = $StatTypes{$field}->{field};
	$sorttype = $SortTypes{$sorttype}->{typecode};
	my $source = (defined $::SelectedFilter)? $::SelectedFilter->filter : $::Library;
	my @list; my $dh; my $dotime;

	$self->{sstore}->clear;
	
	if ($field ne 'title')
	{
		my $href = Songs::BuildHash($field,$source,'gid');

		#calculate album-based stats if so wanted
		if (($field ne 'album') and ($::Options{OPT.'PerAlbumInsteadOfTrack'}) and ($suffix eq ':average'))
		{
			($dh) = Songs::BuildHash($field, $source, undef, $sorttype.':sum');
			my ($ah) = Songs::BuildHash('album', $source, undef, $sorttype.':average');
			for my $gid (keys %$dh) {
				my $albums = AA::Get('album:gid',$field,$gid);
				next unless (scalar@$albums);
				$$dh{$gid} = 0;
				$$dh{$gid} += $$ah{$_} for (@$albums);
				$$dh{$gid} /= scalar@$albums;
			}
		}
		else { ($dh) = Songs::BuildHash($field, $source, undef, $sorttype.$suffix); }


		#we got values, send 'em up!
		my $max = ($::Options{OPT.'AmountOfStatItems'} < (keys %$href))? $::Options{OPT.'AmountOfStatItems'} : (keys %$href);
		my $currentID = ($::SongID)? Songs::Get_gid($::SongID,$field) : -1; 
		@list = (sort { ($self->{butinvert}->get_active)? $dh->{$a} <=> $dh->{$b} : $dh->{$b} <=> $dh->{$a} } keys %$dh)[0..($max-1)];
		
		if ($::Options{OPT.'AddCurrentToStatList'})
		{
			my @cis;
			if (ref($currentID) ne 'ARRAY') { push @cis, $currentID;}
			else {@cis = @$currentID;}
		
			for my $ci (@cis){
				next if ($ci == -1);
				my ($iscurrentIDinlist)= grep { $ci == $list[$_]} 0..$#list;
				push @list, $ci unless (defined $iscurrentIDinlist);
			}
		}
		
		for (0..$#list)
		{
			my $value;
			if ($sorttype eq 'playedlength') { $value = FormatSmalltime($dh->{$list[$_]});}
			else {$value = ($suffix =~ /average/)? sprintf ("%.2f", $dh->{$list[$_]}) : $dh->{$list[$_]};}
			
			my $num = ($_ > ($max-1))? "n/a  " : undef; #this is for the current, if it's not in original list  
			$num ||= ($::Options{OPT.'ShowStatNumbers'})? (($_+1).".   ") : " ";
			$self->{sstore}->set($self->{sstore}->append,0,$num.::PangoEsc(Songs::Gid_to_Display($field,$list[$_])),1,$value,2,$list[$_],3,$field);
		}
	}
	else #single tracks
	{
		Songs::SortList($source,'-'.$sorttype); @list = @$source;
		if ($self->{butinvert}->get_active) { @list = reverse @list;}
		
		my $max = ($::Options{OPT.'AmountOfStatItems'} < (scalar@list))? ($::Options{OPT.'AmountOfStatItems'}) : (scalar@list);
		$#list = ($max-1);
		
		if ($::Options{OPT.'AddCurrentToStatList'})
		{
			my $currentID = ($::SongID)? $::SongID : -1;
			my ($iscurrentIDinlist)= grep { $currentID == $list[$_]} 0..$#list;
			push @list, $currentID unless (defined $iscurrentIDinlist);
		}
		
		for (0..$#list)
		{
			my ($title,$value) = Songs::Get($list[$_],'title',$sorttype);
			if ($sorttype !~ /playedlength/) { $value = sprintf ("%.3f", $value);}
			else {$value = FormatSmalltime($value);}
			
			my $num = ($_ > ($max-1))? "n/a  " : undef; #this is for the current, if it's not in original list  
			$num ||= ($::Options{OPT.'ShowStatNumbers'})? (($_+1).".   ") : " ";
			$self->{sstore}->set($self->{sstore}->append,0,$num.::PangoEsc($title),1, $value,2,$list[$_],3,$field);
		}
	}

	return 1;
}

sub Updateoverview
{
	my $self = shift;
	my @list;

	$_->clear for (@{$self->{ostore_toplist}});
	my @topheads; 
	for (keys %OverviewTopheads) { push @topheads, $_ if ($OverviewTopheads{$_}->{enabled});};
	my $numberofitems;
	
	for my $store (0..$#topheads)
	{
		my $topref;
		if ($topheads[$store] eq 'title')
		{
			my $lr = $::Library;
			my $smode = ($::Options{OPT.'OverviewTopMode'}); $smode =~ s/\:(.+)//;
			Songs::SortList($lr,'-'.$smode);
			$numberofitems = ($::Options{OPT.'OverViewTopAmount'} > (scalar@$lr))? (scalar@$lr) : $::Options{OPT.'OverViewTopAmount'};
			@list = @$lr[0..($::Options{OPT.'OverViewTopAmount'})];
		}
		else
		{
			($topref) = Songs::BuildHash($topheads[$store],$::Library,undef,$::Options{OPT.'OverviewTopMode'});
			$numberofitems = ($::Options{OPT.'OverViewTopAmount'} > (keys %$topref))? (keys %$topref) : $::Options{OPT.'OverViewTopAmount'};
			@list = ((sort { $topref->{$b} <=> $topref->{$a} } keys %$topref)[0..($numberofitems-1)]);
		}
		for my $row (0..($numberofitems-1))
		{
			my @values;
			if ($topheads[$store] eq 'title') {
				my $smode = ($::Options{OPT.'OverviewTopMode'}); $smode =~ s/\:(.+)//;
				my ($title,$value) = Songs::Get($list[$row],'title',$smode);
				push @values, 0,$title,1,$value.' plays',2,$list[$row],3,$topheads[$store];
			}
			else {
				push @values, 0,Songs::Gid_to_Display($topheads[$store],$list[$row]),1,$$topref{$list[$row]}.' plays',2,$list[$row],3,$topheads[$store];
			}

			${$self->{ostore_toplist}}[$store]->set(${$self->{ostore_toplist}}[$store]->append,@values);
		}
	}
	return 1;
}

sub Updatehistory
{
	my $self = shift;
	
	if ($HistoryHash{needupdate})
	{
		delete $sourcehash{$_} for (keys %sourcehash);
		my $source = (($::Options{OPT.'UseHistoryFilter'}) and (defined $::SelectedFilter))? $::SelectedFilter->filter : $::Library; 
		$sourcehash{$$source[$_]} = $_ for (0..$#$source);
		delete $HistoryHash{needupdate};
	}

	CreateHistory() if ((!scalar keys %HistoryHash) or ($HistoryHash{needrecreate}));

	my $amount; my $lasttime = 0;
	if ($::Options{OPT.'HistoryLimitMode'} eq 'days') {
		$lasttime = time-(($::Options{OPT.'AmountOfHistoryItems'}-1)*86400);
		my ($sec, $min, $hour) = (localtime(time))[0,1,2];
		$lasttime -= ($sec+(60*$min)+(3600*$hour));
	}
	else{$amount = ((scalar keys(%HistoryHash)) < $::Options{OPT.'AmountOfHistoryItems'})? scalar keys(%HistoryHash) : $::Options{OPT.'AmountOfHistoryItems'};}

	my %final; my %seen; my @albums;
	
	#we test from biggest to smallest playtime (keys are 'pt'.$playtime) until find $amount songs that are in source
	for my $hk (reverse sort keys %HistoryHash) 
	{
		if ($hk =~ /^pt(\d+)$/) {last unless ($1 > $lasttime);}
		if (defined $sourcehash{$HistoryHash{$hk}->{ID}}) {
			$final{$hk} = $HistoryHash{$hk};
			
			#TODO: Album treshold!
			my $gid = Songs::Get_gid($final{$hk}->{ID},'album');
			unless (defined $seen{$gid}){
				$seen{$gid} = $hk;
				push @albums, $gid;
			} 
			$amount-- if (defined $amount);
		}
		last if ((defined $amount) and ($amount <= 0));
	}

	#then re-populate the hstore
	$self->{hstore}->clear;
	for (reverse sort keys %final)	{
		my $key = $_;
		$key =~ s/^pt//;
		$self->{hstore}->set($self->{hstore}->append,0,FormatRealtime($key),1,$final{$_}->{label},2,$final{$_}->{ID},3,'song');
	}
	
	# then albums
	$self->{hstore_albums}->clear;
	
	for (@albums) {
		my $xref = AA::Get('album_artist:gid','album',$_);
		$self->{hstore_albums}->set($self->{hstore_albums}->append,
			0,AAPicture::pixbuf('album', $_, $::Options{OPT.'CoverSize'}, 1),
			1,Songs::Gid_to_Display('album',$_)."\n by ".Songs::Gid_to_Display('artist',$$xref[0]),
			2,$_,
			3,'album');
	}	
		
	return 1;	
}

sub CreateHistory
{
	for my $ID (@$::Library)
	{
		my $pt = Songs::Get($ID,'lastplay');
		next unless ($pt);#we use playtime as hash key, so it must exist

		$HistoryHash{'pt'.$pt}{ID} = $ID;
		$HistoryHash{'pt'.$pt}{label} = ::ReplaceFields($ID,$::Options{OPT.'HistoryItemFormat'} || '%a - %l - %t');
	}

	delete $HistoryHash{needrecreate} if ($HistoryHash{needrecreate});

	return 1;
}

sub FormatSmalltime
{
	my $sec = shift;

	my $result = '';
	
	if ($sec > 31536000) { $result .= int($sec/31536000).'y '; $sec = $sec%31536000;}
	if ($sec > 2592000) { $result .= int($sec/2592000).'m '; $sec = $sec%2592000;}
	if ($sec > 604800) { $result .= int($sec/604800).'wk '; $sec = $sec%604800;}
	if ($sec > 86400) { $result .= int($sec/86400).'d '; $sec = $sec%86400;}
	$result .= sprintf("%02d",int(($sec%86400)/3600)).':'.sprintf("%02d",int(($sec%3600)/60)).':'.sprintf("%02d",int($sec%60));

	return $result;
}
sub FormatRealtime
{
	my ($realtime,$format) = @_;
	return 'n/a' unless ($realtime);
	my @months = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
	my ($sec, $min, $hour, $day,$month,$year) = (localtime($realtime))[0,1,2,3,4,5]; 	
	$month += 1; $year += 1900;
	my $h12 = ($hour > 11)? $hour-12 : $hour;
	my $ind = ($hour > 11)? 'pm' : 'am';
	$hour = sprintf("%02d",$hour);
	$min = sprintf("%02d",$min);
	$sec = sprintf("%02d",$sec);
	
	my $formatted;
	if ((defined $format) or (defined $::Options{OPT.'HistoryTimeFormat'}))
	{
		$formatted = $format || $::Options{OPT.'HistoryTimeFormat'};
		$formatted =~ s/\%[^dmyHhMSp]//g;
		$formatted =~ s/\%d/$day/g; $formatted =~ s/\%m/$month/g;	
		$formatted =~ s/\%y/$year/g;	$formatted =~ s/\%H/$hour/g;	
		$formatted =~ s/\%h/$h12/g; $formatted =~ s/\%M/$min/g;	
		$formatted =~ s/\%S/$sec/g; $formatted =~ s/\%p/$ind/g;	
	}
	else {$formatted = "".localtime($realtime);}

	return $formatted;
}

sub UpdateCursorCb
{	
	my $textview = shift;
	my (undef,$wx,$wy,undef)=$textview->window->get_pointer;
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$wx,$wy);
	my $iter=$textview->get_iter_at_location($x,$y);
	my $cursor='xterm';
	for my $tag ($iter->get_tags)
	{	next unless $tag->{gid};
		$cursor='hand2';
		last;
	}
	return if ($textview->{cursor}||'') eq $cursor;
	$textview->{cursor}=$cursor;
	$textview->get_window('text')->set_cursor(Gtk2::Gdk::Cursor->new($cursor));
}

sub ButtonReleaseCb
{
	my ($textview,$event) = @_;
	
	my $self=::find_ancestor($textview,__PACKAGE__);
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$event->x, $event->y);
	my $iter=$textview->get_iter_at_location($x,$y);
	for my $tag ($iter->get_tags) {	
		my $gid = $tag->{gid}; my $field = $tag->{field};
		if ($field ne 'title') {
			::PopupAAContextMenu({gid=>$gid,self=>$textview,field=>$field,mode=>'S'});
		}
		else{
			::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $textview, IDs => [$gid]});
		}
	}

	return ::TRUE; #don't want any default popups
}

sub HTVContext 
{
	my ($treeview, $event) = @_;
	return 0 unless $treeview;

	my @paths = $treeview->get_selection->get_selected_rows;
	return unless (scalar@paths);

	my $store=$treeview->{store};
	my @IDs; my $field;# this will be same for all rows, either 'song' or 'album'
	
	for (@paths)
	{
		my $iter=$store->get_iter($_);
		my $ID=$store->get( $store->get_iter($_),2);
		$field=$store->get( $store->get_iter($_),3);
		push @IDs,$ID;
	}

	if ($event->button == 2) { 
		if ($field eq 'song') {::Enqueue(\@IDs);}
		else {}		 
	}
	elsif ($event->button == 3) {
		if ($field ne 'song')
		{
			if (scalar@IDs == 1) {::PopupAAContextMenu({gid=>$IDs[0],self=>$treeview,field=>$field,mode=>'S'});}
			else {
				my @idlist;
				for (@IDs) {push @idlist , @{AA::Get('idlist',$field,$_)};}
				::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@idlist});
			}
		}
		else {::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@IDs});}			
	}
	elsif (($event->button == 1) and ($event->type  eq '2button-press') and (scalar@IDs == 1)) {
		if ($field ne 'title'){
			my $aalist = AA::Get('idlist',$field,$IDs[0]);
			Songs::SortList($aalist,$::Options{Sort} || $::Options{Sort_LastOrdered});
			::Select( filter => Songs::MakeFilterFromGID($field,$IDs[0])) if ($::Options{OPT.'FilterOnDblClick'});
			::Select( song => $$aalist[0], play => 1);
		}
		else {::Select(song => $IDs[0], play => 1);}
	}
	else {return 0;}
	
	return 1;
}

sub STVContextPress
{
	my ($treeview, $event) = @_;
	return 0 unless $treeview;

	my $store=$treeview->{store};
	my @paths = $treeview->get_selection->get_selected_rows;

	return unless (scalar@paths);
	my @IDs; my $field;
	
	for (@paths)
	{
		my $iter=$store->get_iter($_);
		my $ID=$store->get( $store->get_iter($_),2);
		$field=$store->get( $store->get_iter($_),3);
		push @IDs,$ID;
	}

	if ($event->button == 3)
	{
		if ($field ne 'title'){
			if (scalar@IDs == 1) {::PopupAAContextMenu({gid=>$IDs[0],self=>$treeview,field=>$field,mode=>'S'});}
			else {
				my @idlist;
				for (@IDs) {push @idlist , @{AA::Get('idlist',$field,$_)};}
				::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@idlist});
			}
		}
		else {
			::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@IDs});
		}
	}
	elsif (($event->button == 1) and ($event->type  eq '2button-press') and (scalar@IDs == 1)) {
		if ($field ne 'title'){
			my $aalist = AA::Get('idlist',$field,$IDs[0]);
			Songs::SortList($aalist,$::Options{Sort} || $::Options{Sort_LastOrdered});
			::Select( filter => Songs::MakeFilterFromGID($field,$IDs[0])) if ($::Options{OPT.'FilterOnDblClick'});
			::Select( song => $$aalist[0], play => 1);
		}
		else { ::Select(song => $IDs[0], play => 1);}
	}
	else { return 0;}
	
	return 1;
}

sub STVChanged
{
	my $treeselection = shift;
	
	return unless ($::Options{OPT.'SetFilterOnLeftClick'});
	
	my $treeview = $treeselection->get_tree_view;	
	my $store=$treeview->{store};
	my @paths = $treeview->get_selection->get_selected_rows;
	
	return unless (scalar@paths);
	my @Filters; my $field;
	
	for (@paths)
	{
		my $iter=$store->get_iter($_);
		my $GID=$store->get( $store->get_iter($_),2);
		$field=$store->get( $store->get_iter($_),3);
		next if ($field eq 'title');
		push @Filters, Songs::MakeFilterFromGID($field,$GID);
	}
	
	my $fnew = Filter->newadd(0, @Filters);
	my $filt = (defined $::SelectedFilter)? Filter->newadd(1,$::SelectedFilter,$fnew) : $fnew; 
	
	::SetFilter($treeview,$filt,1);
	
	return 1;
}

sub SongChanged 
{
	my ($widget,$force) = @_;
	
	return if (($lastID == $::SongID) and (!$force));
	
	my $albumhaschanged = (Songs::Get_gid($lastID,'album') != Songs::Get_gid($::SongID,'album'))? 1 : 0; 
	
	$lastID = $::SongID;
	
	my $self=::find_ancestor($widget,__PACKAGE__);
	
	if ($self->{site} eq 'statistics')
	{
		$force = 1 if (($::Options{OPT.'StatViewUpdateMode'} eq $statupdatemodes{songchange}) 
						or 
					  (($::Options{OPT.'StatViewUpdateMode'} eq $statupdatemodes{albumchange}) and ($albumhaschanged)));
	} 

	UpdateSite($self,$self->{site},$force);
	
	return 1;
}
sub SongPlayed
{
	my ($self,$ID, $playedEnough, $StartTime, $seconds, $coverage_ratio, $Played_segments) = @_;

	AddToHistory($self,$ID,$StartTime) if (($playedEnough) or ((!$::Options{OPT.'RequirePlayConditions'}) and ($lastAdded{ID} != $ID))); 

	$::Options{OPT.'TotalPlayTime'} = $globalstats{playtime}+$seconds; 
	$::Options{OPT.'TotalPlayTracks'} = ($globalstats{playtrack}+1) if ($playedEnough);
	$globalstats{playtime} = $::Options{OPT.'TotalPlayTime'};
	$globalstats{playtrack} = $::Options{OPT.'TotalPlayTracks'};
	
	return 1;
}

sub AddToHistory
{
	my ($self,$ID,$playtime) = @_;	

	$lastAdded{ID} = $ID;
	$lastAdded{playtime} = $playtime;
	
	$HistoryHash{'pt'.$playtime}{ID} = $ID;
	$HistoryHash{'pt'.$playtime}{label} = join " - ", ::ReplaceFields($ID,$::Options{OPT.'HistoryItemFormat'} || '%a - %l - %t');

	$self->{needsupdate} = ($self->{site} eq 'history')? 1 : 0;
	UpdateSite($self,'history');

	LogHistory($ID,$playtime) if ($::Options{OPT.'LogHistoryToFile'});
	
	return 1;
}

sub LogHistory
{
	my ($ID,$playtime) = @_;
	return unless (($ID) and ($playtime));
	
	my $content = FormatRealtime($playtime)."\t".::ReplaceFields($ID,$::Options{OPT.'HistoryItemFormat'} || '%a - %l - %t');
		
	open my $fh,'>>',$LogFile or warn "Error opening '$LogFile' for writing : $!\n";
	print $fh $content   or warn "Error writing to '$LogFile' : $!\n";
	close $fh;

	return 1;	
}

1