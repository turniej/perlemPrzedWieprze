#!/usr/bin/perl

#################################################################################################################
##
##  perlemPrzedWieprze v 0.1
##  Copyright 2011-2012 Piotr Duda
##
##    This program is free software; you can redistribute it and/or modify
##    it under the terms of the GNU Affero General Public License as 
##    published by the Free Software Foundation; either version 3 of the 
##    License, or (at your option) any later version.
##
##    This program is distributed in the hope that it will be useful,
##    but WITHOUT ANY WARRANTY; without even the implied warranty of
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##    GNU Affero General Public License for more details.
##
##    You should have received a copy of the GNU Affero General Public
##    License along with this program; if not, write to the Free Software
##    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
##
##    Niniejszy program jest wolnym oprogramowaniem; możesz go
##    rozprowadzać dalej i/lub modyfikować na warunkach Powszechnej
##    Licencji Publicznej Affero GNU, wydanej przez Fundację Wolnego
##    Oprogramowania - według wersji 3 tej Licencji lub (według twojego
##    wyboru) którejś z późniejszych wersji.
##
##    Niniejszy program rozpowszechniany jest z nadzieją, iż będzie on
##    użyteczny - jednak BEZ JAKIEJKOLWIEK GWARANCJI, nawet domyślnej
##    gwarancji PRZYDATNOŚCI HANDLOWEJ albo PRZYDATNOŚCI DO OKREŚLONYCH
##    ZASTOSOWAŃ. W celu uzyskania bliższych informacji sięgnij do
##    Powszechnej Licencji Publicznej Affero GNU.
##
##    Z pewnością wraz z niniejszym programem otrzymałeś też egzemplarz
##    Powszechnej Licencji Publicznej Affero GNU (GNU AfferoGeneral
##    Public License); jeśli nie - napisz do Free Software Foundation, Inc.,
##    59 Temple Place, Fifth Floor, Boston, MA  02110-1301  USA
##
##
#################################################################################################################

use strict;
use utf8;
use Encode;
use POSIX qw(locale_h);
use Data::Dumper;
use Time::HiRes;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use URI;
use LWP;

##
## stałe
##

my $KATALOG_Z_DANYMI = "./ppw-dane";
my $NAZWA_PLIKU_Z_DANYMI = "./ppw-ekstrakt.txt";
my $NAZWA_PLIKU_Z_INDEKSAMI = "./ppw-indeksy.txt";
my $NAZWA_PLIKU_ARCHIWUM = "./txt-liryka.zip";
my $ADRES_PLIKU_ARCHIWUM = "http://www.wolnelektury.pl/media/packs/txt-liryka.zip";
my $DLUGOSC_WIERSZA_ZRD_MIN = 15;
my $DLUGOSC_WIERSZA_ZRD_MAX = 90; #80;
my $DLUGOSC_RYMU_MIN = 3;
my $DLUGOSC_RYMU_MAX = 6;

my $WIERSZ_LICZBA_ZWROTEK_MIN = 2;
my $WIERSZ_LICZBA_ZWROTEK_MAX = 4;
# poniższe 2 stałe powinny być parzyste
my $WIERSZ_LICZBA_WERSOW_W_ZWROTCE_MIN = 2;
my $WIERSZ_LICZBA_WERSOW_W_ZWROTCE_MAX = 6;

my $WIERSZ_LICZBA_ZNAKOW_MAX = 1000;
my $WIERSZ_ODLEGLOSC_RYMU_MIN = 5;

my $SAMOGLOSKI = "eyuioaęóąEYUIOAĘÓĄ";
my $TOLERANCJA_RYTMU = 2;

# przy zagniezdzonym nawiasie                             |                      |
# ustawiac go na koncu wyrazenia                          v                      v
my @RE_FRAGMENTY = ("k|g", "b|p", "sz|rz|ż", "dz|c(?![hiz])", "ę|e", "t|d(?![zżź])", "y|i", "w|f", "ó|u", "dź|ć");
# na razie wycięte: "o|ą", 

##
## zmienne globalne
##

my @zrodloDane = ();
my $zrodloLiczbaWierszy = 0;
my $wierszLiczbaZwrotek = 0;
my $wierszLiczbaWersowWZwrotce = 0;
my $wierszCzyRymyNaPrzemian = 0;
my $wierszCzyRownacRytm = 0;
my @wylosowaneWersy = ();

my $ileCzasuCzyRymuje = 0;
my $ileCzasuWyciagnijRym = 0;
my $ileCzasuWyciagnijOstatnieSlowo = 0;
my $ileCzasuPrzygotujWyrazenieRymujace = 0;
my $ileCzasuSzukanieRytmow = 0;

my %haszIndeksow = ();

my %benchmarki = ();
my $nrLiniiEkstraktu = 0;

##
## kod
##

setlocale(LC_ALL, "pl_PL.utf8");
start();

sub start {
	unless (-e $NAZWA_PLIKU_Z_DANYMI && -e $NAZWA_PLIKU_Z_INDEKSAMI)  {
		print encode("UTF-8", "Brak danych źródłowych.\n\nRozpoczęcie próby zbudowania danych źródłowych. To może trochę potrwać!!\n\n");
		przygotujDaneZrodlowe();
		
		print encode("UTF-8", "Autokonfiguracja zakończyła się sukcesem.\nUruchom skrypt ponownie by rozpocząć generowanie „utworu“ :-).\n");
		exit 0;
	}
	open my $uchwytPlikuZDanymi, "< $NAZWA_PLIKU_Z_DANYMI" or die "Nie można zaczerpnąć z danych źródłowych (problem z plikem: $NAZWA_PLIKU_Z_DANYMI [$!])\n";
	@zrodloDane = <$uchwytPlikuZDanymi>;
	$zrodloLiczbaWierszy = $.;
	close $uchwytPlikuZDanymi;
	
	losujParametry();
	generujWiersz();
	wypiszWiersz();

#	wypiszBenchmarki();
}


sub generujWiersz {
	my $liczbaWersowDoLosowania = $wierszLiczbaWersowWZwrotce * $wierszLiczbaZwrotek / 2;

	wczytajIndeksy();

	my $najwyzszyRytm = 0;
	for(my $i=0; $i < $liczbaWersowDoLosowania; $i++) {
		my $losowa = int(rand($zrodloLiczbaWierszy));
		my $wylosowany = decode("UTF-8", $zrodloDane[$losowa]);
		my ($rytmWersu) = ($wylosowany =~ /^(\d+):/);
		$wylosowany =~ s/^[^\|]*\|//;
		my %daneWersu = ();
		$daneWersu{"nrWersu"} = $losowa;
		$daneWersu{"wersOryginalny"} = $wylosowany;
		$daneWersu{"rytmWersu"} = $rytmWersu;
		$daneWersu{"wyrazenieRymujace"} = przygotujWyrazenieRymujace(wyciagnijRym($wylosowany));
		$daneWersu{"ostatnieSlowo"} = wyciagnijOstatnieSlowo($wylosowany);
		$daneWersu{"ostatniaLitera"} = wyciagnijOstatniaLitere($daneWersu{"ostatnieSlowo"});
		my @rymujace = ();
		$daneWersu{"rymujace"} = [ @rymujace ];
		$wylosowaneWersy[$i] = \%daneWersu;
		if ($rytmWersu > $najwyzszyRytm) {
			$najwyzszyRytm = $rytmWersu;
		}
	}
	my @rymujaceDlaWersu = ();
	my $kursor = 0;

	## szukanie rymów po indeksach
#	my $benchmark0 = wlaczBenchmark();
	foreach my $wers (@wylosowaneWersy) {
		foreach my $literka (keys %haszIndeksow) {
			if ($literka =~ /$wers->{ostatniaLitera}/) {
				foreach my $nrLinii ( @{$haszIndeksow{$literka}} ) {
					if ( ($nrLinii+$WIERSZ_ODLEGLOSC_RYMU_MIN) < $wers->{"nrWersu"} || ($nrLinii-$WIERSZ_ODLEGLOSC_RYMU_MIN) > $wers->{"nrWersu"} ) {
						if (czyRymuje($wers->{"wyrazenieRymujace"}, $wers->{"ostatnieSlowo"}, decode("UTF-8", $zrodloDane[$nrLinii]))) {
							push( @{$wers->{"rymujace"}}, $nrLinii);
						}
					}
				}
			}
		}
	}
#	podliczBenchmark($benchmark0, "Szukanie rymów po indeksach");
	
	## szukanie rymów po całości
#	my $benchmark = wlaczBenchmark();
#	# przebieg danych źródłowych (szukanie rymów)
#	foreach my $linia (@zrodloDane) {
#		my $biezacyWers = 0;
#		foreach my $wers (@wylosowaneWersy) {
#			if ( ($kursor+$WIERSZ_ODLEGLOSC_RYMU_MIN) < $wers->{"nrWersu"} || ($kursor-$WIERSZ_ODLEGLOSC_RYMU_MIN) > $wers->{"nrWersu"} ) {
#				if (czyRymuje($wers->{"wyrazenieRymujace"}, $wers->{"ostatnieSlowo"}, decode("UTF-8", $linia))) {
#					push( @{$wers->{"rymujace"}}, $kursor);
#				}
#			}
#			$biezacyWers++;
#		}
#		$kursor++;
#	}
#	podliczBenchmark($benchmark, "Szukanie rymów");
	
	## wylosowanie wierszy rymujących
	foreach my $wers (@wylosowaneWersy) {
		my $wylosowany;
		## dla tych co nie mają rymu
		if ( scalar @{$wers->{"rymujace"}} == 0 ) {
			my $losowa = int(rand($zrodloLiczbaWierszy));
			while ($losowa == $wers->{"nrWersu"}) {
				$losowa = int(rand($zrodloLiczbaWierszy));
			}
			$wylosowany = $zrodloDane[ $losowa ];
			my ($rytmWersu) = ($wylosowany =~ /^(\d+):/);
			$wylosowany =~ s/^[^\|]*\|//;
			$wers->{"wersDoPary"} = decode("UTF-8", $wylosowany);
			$wers->{"rytmWersuDoPary"} = $rytmWersu;
			if ($rytmWersu > $najwyzszyRytm) {
				$najwyzszyRytm = $rytmWersu;
			}
		} else { ## dla pozostałych
			my $losowa = int(rand( scalar @{$wers->{"rymujace"}} ));
			my $nrWersuDoPary = $wers->{"rymujace"}[$losowa];
			$wylosowany = $zrodloDane[ $nrWersuDoPary ];
			my ($rytmWersu) = ($wylosowany =~ /^(\d+):/);
			$wylosowany =~ s/^[^\|]*\|//;
			$wers->{"wersDoPary"} = decode("UTF-8", $wylosowany);
			$wers->{"rytmWersuDoPary"} = $rytmWersu;
			if ($rytmWersu > $najwyzszyRytm) {
				$najwyzszyRytm = $rytmWersu;
			}
		}
	}

	## wyrownywanie rytmu

	my $najnizszyRytm = $najwyzszyRytm - 2*$TOLERANCJA_RYTMU;
#	my $benchmark2 = wlaczBenchmark();
	if ($wierszCzyRownacRytm) {
		foreach my $wers (@wylosowaneWersy) {
			if ($wers->{"rytmWersu"} < $najnizszyRytm) {
				$wers->{"wersOryginalny"} = wyrownajRytm($wers->{"wersOryginalny"}, $wers->{"rytmWersu"}, ($najnizszyRytm + $TOLERANCJA_RYTMU));
			}
			if ($wers->{"rytmWersuDoPary"} < $najnizszyRytm) {
				$wers->{"wersDoPary"} = wyrownajRytm($wers->{"wersDoPary"}, $wers->{"rytmWersuDoPary"}, ($najnizszyRytm + $TOLERANCJA_RYTMU));
			}
		}	
	}
#	podliczBenchmark($benchmark2, "Wyrównanie rytmów");
}

sub wyrownajRytm {
	my ($wersik, $aktualnyRytm, $docelowyRytm) = @_;
	my @kawalki = split(/\s/, $wersik);
	my $gdzieWklejamy = int( rand( (scalar @kawalki)-1 )) + 1;
	my $ileDodano = 0;
	my $doWklejenia;

	do {
		$ileDodano = 0;
		$doWklejenia = "";
		my $losowa = int(rand($zrodloLiczbaWierszy));
		my $wylosowany = decode("UTF-8", $zrodloDane[$losowa]);
		$wylosowany =~ s/^[^\|]*\|//;
		$wylosowany =~ s/[^\w\s,.–—-]//g;
		my @kawalkiWylosowanego = split(/\s/, $wylosowany);
		for(my $i=2; $i < (scalar @kawalkiWylosowanego)-1; $i++) {
			$doWklejenia .= $kawalkiWylosowanego[$i] . " ";
			my $tmp = $kawalkiWylosowanego[$i];
			$tmp =~ s/[$SAMOGLOSKI]+/@/g;
			$tmp =~ s/[^@]//g;
			$ileDodano += length($tmp);
			if ( ($aktualnyRytm + $ileDodano) >= $docelowyRytm ) {
				last;
			}
		}
	} while ( ($aktualnyRytm + $ileDodano) > ($docelowyRytm + $TOLERANCJA_RYTMU) || ($aktualnyRytm + $ileDodano) < ($docelowyRytm - $TOLERANCJA_RYTMU) );
	$doWklejenia =~ s/\s+$//;

	my $wynik = "";
	my $i;
	for ($i = 0; $i < $gdzieWklejamy; $i++) {
		$wynik .= $kawalki[$i] . " ";
	}
	$wynik .= $doWklejenia . " ";
	for ($i = $gdzieWklejamy; $i < scalar @kawalki; $i++) {
		$wynik .= $kawalki[$i] . " ";
	}
	$wynik =~ s/\s*$//;

	return $wynik;
}

sub wypiszWiersz {
	my $wers;
	my $nrWersu = 0;
	my $nrZwrotki = 0;
	my $w2ZpoprzedniegoPrzebiegu = "";
	wytnijNadmiar();
	my $wszystkichWierszy = (scalar @wylosowaneWersy)*2;
	print "\n";
	foreach $wers (@wylosowaneWersy) {
		my $wciecie = "";
		my $zakonczenieDrugiegoWersu = ",";
		if ( ($nrZwrotki % 2) == 1 ) {
			$wciecie = "\t";
		}

		$nrWersu += 2;
		$wszystkichWierszy -= 2;
		if ( ($nrWersu % $wierszLiczbaWersowWZwrotce) == 0 || $wszystkichWierszy == 0) {
			$nrZwrotki++;
			$zakonczenieDrugiegoWersu = ".";
		}

		my $w1 = $wers->{"wersOryginalny"};
		my $w2 = $wers->{"wersDoPary"};
		$w1 =~ s/[\s\W]*$//;
		$w2 =~ s/[\s\W]*$//;
		$w1 = $wciecie . ucfirst($w1);
		$w2 = $wciecie . ucfirst($w2);
		print encode("UTF-8", $w1) . ",\n";
		if ($wierszCzyRymyNaPrzemian) {
			if (length($w2ZpoprzedniegoPrzebiegu)==0) {
				$w2ZpoprzedniegoPrzebiegu = $w2;
			} else {
				print encode("UTF-8", $w2ZpoprzedniegoPrzebiegu) . ",\n";
				print encode("UTF-8", $w2) . $zakonczenieDrugiegoWersu . "\n";
				$w2ZpoprzedniegoPrzebiegu = "";
			}
		} else {
			print encode("UTF-8", $w2) . $zakonczenieDrugiegoWersu . "\n";
		}

		if ( ($nrWersu % $wierszLiczbaWersowWZwrotce) == 0) {
			print "\n";
		}
	}
	print "\n";
}

sub wytnijNadmiar {
	my $licznikZnakow = 0;
	my $wers;
	foreach $wers (@wylosowaneWersy) {
		$licznikZnakow += length(encode("UTF-8", $wers->{"wersOryginalny"})) + length(encode("UTF-8", $wers->{"wersDoPary"}));
	}
	my $marginesik = $wierszLiczbaWersowWZwrotce*$wierszLiczbaZwrotek*2+4;
	while ( ($licznikZnakow + $marginesik) > $WIERSZ_LICZBA_ZNAKOW_MAX ) {
		$wers = pop(@wylosowaneWersy);
		$licznikZnakow -= (length(encode("UTF-8", $wers->{"wersOryginalny"})) + length(encode("UTF-8", $wers->{"wersDoPary"})));
	}
}

sub losujParametry {
	$wierszLiczbaZwrotek = int(rand( ($WIERSZ_LICZBA_ZWROTEK_MAX+1 - $WIERSZ_LICZBA_ZWROTEK_MIN) )) + $WIERSZ_LICZBA_ZWROTEK_MIN;
	$wierszLiczbaWersowWZwrotce = int(rand( ($WIERSZ_LICZBA_WERSOW_W_ZWROTCE_MAX+1 - $WIERSZ_LICZBA_WERSOW_W_ZWROTCE_MIN) )) + $WIERSZ_LICZBA_WERSOW_W_ZWROTCE_MIN;
	# parzysta liczba wierszy
	$wierszLiczbaWersowWZwrotce = $wierszLiczbaWersowWZwrotce - ($wierszLiczbaWersowWZwrotce % 2);

#	$wierszLiczbaZwrotek = 4;
#	$wierszLiczbaWersowWZwrotce = 6;

	if ( int( rand(3) ) % 2 == 0 && ($wierszLiczbaWersowWZwrotce % 4) == 0 ) {
		$wierszCzyRymyNaPrzemian = 1; 
	} else {
		$wierszCzyRymyNaPrzemian = 0;
	}
	if ( int( rand(3) ) != 0) {
		$wierszCzyRownacRytm = 1;
	}
	
#	print "Wylosowane parametry wiersza:\n";
#	print "             zwrotek:\t $wierszLiczbaZwrotek \n";
#	print "    wersow w zwrotce:\t $wierszLiczbaWersowWZwrotce\n";
#	print "czy rymy na przemian:\t $wierszCzyRymyNaPrzemian\n";
#	print "     czy rownac rytm:\t $wierszCzyRownacRytm\n";
}


sub czyRymuje {
	my($wyrazenie, $ostatSlowo, $wersik) = @_;
#	my $benchmark = wlaczBenchmark();
	my $pasuje = 0;
	my $rym = wyciagnijRym($wersik);
	
	if (!defined($rym) || length($rym)==0) {
		return $pasuje;
	}
	
	if ( $rym =~ /$wyrazenie$/i ) {
		if ( $ostatSlowo ne wyciagnijOstatnieSlowo($wersik)) {
				$pasuje = 1;
		}
	}
	
#	podliczBenchmark($benchmark, "czyRymuje");
	return $pasuje;
}

sub wyciagnijOstatnieSlowo {
	my ($wersik) = @_;
	my $ostatSlowo = "";
	$wersik =~ s/[^\w\s]//g;
	($ostatSlowo) = ( $wersik =~ /\s([\w]+)[\W]*$/);
	$ostatSlowo = lc($ostatSlowo);
	return $ostatSlowo;
}

sub wyciagnijOstatniaLitere {
	my ($slowo) = @_;
	
	my ($lit) = ($slowo =~ /(.)$/);
	return przygotujWyrazenieRymujace($lit);
}

sub przygotujWyrazenieRymujace {
	my($rym) = @_;
my $start = [Time::HiRes::gettimeofday()];

	my $wyrazenie = "";
	my $pasowal;
	while (length($rym) > 0) {
		$pasowal = 0;
		foreach my $frag (@RE_FRAGMENTY) {
			if ($rym =~ /^($frag)/i) {
				if (length($rym) > $DLUGOSC_RYMU_MIN) {
					if (length($wyrazenie) == 0) {
						$wyrazenie .= "(" . $frag . ")?";
					} else {
						$wyrazenie = "(" . $wyrazenie . "(" . $frag . "))?";
					}
				} else {
					$wyrazenie .= "(" . $frag . ")";
				}
				$rym =~ s/^($frag)//i;
				$pasowal = 1;
				last;
			}
		}
		if (!$pasowal) {
			if (length($rym) > $DLUGOSC_RYMU_MIN) {
				if (length($wyrazenie) == 0) {
					$wyrazenie .= substr($rym, 0, 1) . "?";
				} else {
					$wyrazenie = "(" . $wyrazenie . substr($rym, 0, 1) . ")?";
				}
			} else {
				$wyrazenie .= substr($rym, 0, 1);
			}
			$rym = substr($rym, 1);
		}
	}
#	print encode("UTF-8", $wyrazenie) . "\n";
$ileCzasuPrzygotujWyrazenieRymujace += Time::HiRes::tv_interval($start);
	return $wyrazenie;
}

sub wyciagnijRym {
	my($czystyWers) = @_;

	$czystyWers =~ s/\W//g;
	my ($rymik) = ($czystyWers =~ /(\w{6})$/);

	return $rymik;
}

sub wlaczBenchmark {
	return [Time::HiRes::gettimeofday()];
}

sub podliczBenchmark {
	my($benchmark, $klucz) = @_;
	if (! exists($benchmarki{$klucz})) {
		$benchmarki{$klucz} = 0;
	}
	$benchmarki{$klucz} += Time::HiRes::tv_interval($benchmark);
}

sub wypiszBenchmarki {
	print "\n";
	foreach my $klucz (keys %benchmarki) {
		printf "%s: %f sekund.\n", encode("UTF-8", $klucz), $benchmarki{$klucz};
	}
	print "\n";
}

sub wczytajIndeksy {
#	my $benchmark = wlaczBenchmark();
	open (INDEKSY_UCHWYT, $NAZWA_PLIKU_Z_INDEKSAMI) or die print(encode("UTF-8", "$NAZWA_PLIKU_Z_INDEKSAMI - Nie mogę otworzyć pliku z indeksami [$!]. Usuń plik $NAZWA_PLIKU_Z_DANYMI i uruchom skrypt ponownie by utworzyć również plik z indeksami!\n"));
	my @indeksyDane = <INDEKSY_UCHWYT>;
	close INDEKSY_UCHWYT;
	
	foreach my $liniaZIndeksami (@indeksyDane) {
		my $literka;
		my $indeksy;
		($literka, $indeksy) = ($liniaZIndeksami =~ /^([^:]+):(.*)$/);
		my @tablica =  split(/,/, $indeksy);
		$haszIndeksow{$literka} = \@tablica;
	}

#	podliczBenchmark($benchmark, "Wczytanie pliku indeksów");

}

sub przygotujDaneZrodlowe {
	my $plik;
	unless (-d $KATALOG_Z_DANYMI) {
		mkdir($KATALOG_Z_DANYMI) or die "Nie można utworzyć katalogu na dane źródłowe [$!]\n";
	}
	my @wszystkiePliki = glob("$KATALOG_Z_DANYMI/*.txt");
	unless (scalar @wszystkiePliki > 0) {
		unless (-e $NAZWA_PLIKU_ARCHIWUM) { 
			# pobranie z sieci
			my $agent = LWP::UserAgent->new;

			my $url = URI->new($ADRES_PLIKU_ARCHIWUM);
			$url->query_form();
			my $plik = $agent->get($url);
			open (PLIK_UCHWYT,">",$NAZWA_PLIKU_ARCHIWUM) or die print(encode("UTF-8", "$NAZWA_PLIKU_ARCHIWUM - Nie mogę zapisać pliku [$!]\n"));
			binmode(PLIK_UCHWYT);
			print PLIK_UCHWYT $plik->content;
			close PLIK_UCHWYT;
			print(encode("UTF-8", "Plik archiwalny z liryką został pobrany z sieci.\n"));
		}
		# rozpakowanie
		my $zip = Archive::Zip->new($NAZWA_PLIKU_ARCHIWUM) or die print(encode("UTF-8", "Nie mogę rozpakować archiwum z liryką [$!]\n"));
		foreach my $file ($zip->members) {
			$file->extractToFileNamed($KATALOG_Z_DANYMI . "/" . $file->fileName);
		}
		print(encode("UTF-8", "Pliki z liryką zostały rozpakowane.\n"));
		@wszystkiePliki = glob("$KATALOG_Z_DANYMI/*.txt");
    }
		
	open my $uchwytPlikuZDanymi, "> $NAZWA_PLIKU_Z_DANYMI" or die print(encode("UTF-8", "Nie można zapisać danych (problem z plikem: $NAZWA_PLIKU_Z_DANYMI [$!])\n"));
	foreach $plik (@wszystkiePliki) {
		oczyscDane($plik, $uchwytPlikuZDanymi);
	}
	print(encode("UTF-8", "Dane zostały oczyszczone.\nEkstrakt został przygotowany.\n"));
	
	open INDEKSY, "> $NAZWA_PLIKU_Z_INDEKSAMI" or die print(encode("UTF-8", "Nie można zapisać indeksów do pliku indeksow [$!]\n"));
	foreach my $ost (keys %haszIndeksow) {
		print INDEKSY encode("UTF-8", "$ost:" );
		print INDEKSY join(",", @{ $haszIndeksow{$ost} });
		print INDEKSY "\n";
	}
	close(INDEKSY);
	print(encode("UTF-8", "Indeksy zostały przeliczone.\nPlik indeksów został zapisany\n"));

	close $uchwytPlikuZDanymi;
}

sub wyliczRytm {
	my($linia) = @_;
	
	$linia =~ s/[^\w\s]//g;
	$linia =~ s/[$SAMOGLOSKI]+/@/g;
	my $all = $linia;
	$all =~ s/[^@]//g;
	my $rytmCalosci = length( $all );
	return $rytmCalosci . ":";
}

sub oczyscDane {
	my($plik, $uchwytPlikuZDanymi) = @_;

	my $pierwszeSmieci = 0;
	my $ostatniSmiec = 0;

	open(TRESC, ("$plik")) || die "Nie udało się wyłuskać danych! (problem z plikiem: $plik [$!])\n";
	my @tresc = <TRESC>;
	close(TRESC);

	my $linia;
	foreach $linia (@tresc) {
		$linia =~ s/^\s+//g;
		$linia =~ s/\s+$//g;
		if ( $pierwszeSmieci < 3) {
			if ( length($linia) > 0 ) {
				$pierwszeSmieci = 0;
			} else {
				$pierwszeSmieci++;
			}
		} elsif ( $ostatniSmiec < 1 ) {
			if ($linia =~ /-----/ || $linia =~ /Komentarz J/) {
				$ostatniSmiec = 1;
			} else {
				# usuwanie nadmiaru śmieciowych znaków
				my $wers = decode("UTF-8", $linia);
				# podmiana dziwnych literek spoza ASCII i polskich ogonków UTF-8 na normalne
				$wers =~ tr/аАМоОсС/aAMoOcC/;
				$wers =~ s/[^\w\s,:;!?–—-]//g;
				$wers =~ s/\s{2,}/ /g;
				if (length($wers) >= $DLUGOSC_WIERSZA_ZRD_MIN && length($wers) <= $DLUGOSC_WIERSZA_ZRD_MAX) {
					my $rytm = wyliczRytm($wers); 
					$linia = encode("UTF-8", $wers);
					if ($rytm <= 16 && $rytm =~ /^[^0]/ && $wers !~ /[\d]/ && $wers !~ /\W\w{1}\W*$/) {
						my ($ostatni) = ($wers =~ /(\w)\W*$/);
						$ostatni = lc($ostatni);
						if (!exists($haszIndeksow{$ostatni})) {
							@{$haszIndeksow{$ostatni}} = ();
						}
						push (@{$haszIndeksow{$ostatni}}, $nrLiniiEkstraktu);

						print $uchwytPlikuZDanymi "$rytm|$linia\n";
						$nrLiniiEkstraktu++;
					}
				}
			}
		}
	}
}



