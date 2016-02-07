#!/usr/bin/perl

use Date::Parse;
use File::Basename;
use File::stat;
use Getopt::Long;
use POSIX;
use strict;
use Time::Local;

my $dossierScript = dirname($0);
do "$dossierScript/utils.pl";

# ----- options de la ligne de commande -----
my $utilisation = "utilisation : $0 [-h] | -d dossier [-f] [-s]";

my $texteAide = "Corrige les noms des fichiers avec accents
     -h | --help | -a | --aide : cette aide

     -d | --dossier : nom du dossier a traiter
     -f | --force : ne verifie pas que les fichiers ne sont pas en cours d'utilisation
     -s | --simule : simule le fonctionnement, ne fait aucun renommage\n";

Getopt::Long::Configure("bundling");
my ($aide, $dossier, $force, $simule);
GetOptions(
           "aide|a|help|h" => \$aide,
           "dossier|d=s" => \$dossier,
           "force|f" => \$force,
           "simule|s" => \$simule
          ) or die $utilisation;

if ($aide) {
  print "$utilisation\n";
  print "$texteAide\n";
  exit 0;
}
die $utilisation if (! $dossier);

# verifie l'existence du dossier
die "dossier $dossier non trouve !" if (! -d $dossier);



# ----- fichierEnCoursDUtilisation -----
sub fichierEnCoursDUtilisation {
  my ($nomFichier) = @_;
  $nomFichier = prepareFichierPourShell($nomFichier);

  # verifie si le fichier est utilise
  system("lsof $nomFichier >/dev/null");
  my $valeurRetour = $? >> 8;
  if ($valeurRetour == 0) {
    print "$nomFichier en cours d'utilisation d'apres lsof.\n";
    return 1;
  }

  # verifie si le fichier a ete accede au cours des 12 dernieres heures
  my $resultatCommande = `ls -lud $nomFichier`;
  #print "ls -lud $nomFichier: '$resultatCommande'\n";
  # -rw-r--r--  1 xavier  xavier  0 Jan  6 00:10 tata/truc iÌ‚.txt
  if ($resultatCommande =~ /\S+\s+\d+\s+\S+\s+\S+\s+\d+\s+(\w+\s+\d+\s+\d+:\d+)\s+.*/) {
    my $heureDerniereUtilisation = str2time($1);
    my $difference = time - $heureDerniereUtilisation;
    if ($difference < 12*60*60) {
      print "$nomFichier modifie le " . strftime('%d/%m/%Y %H:%M:%S', localtime($heureDerniereUtilisation))
                      . ", soit il y a " . formatteDuree($difference) . ".\n";
      return 1;
    }
  }

  return 0;
}


# ----- traiteDossier -----
sub traiteDossier {
  my ($dossierEnCours) = @_;
  die "dossier $dossierEnCours non trouve !" if (! -d $dossierEnCours);

  $dossierEnCours = prepareFichierPourShell($dossierEnCours);
  my @nomsFichiers = <$dossierEnCours/*>;
  foreach my $nomFichier (@nomsFichiers) {
    my ($nomFichierBase, $chemin) = fileparse($nomFichier);
    my $nomFichierNettoyeBase = $nomFichierBase;
    $nomFichierNettoyeBase =~ s/[^[:ascii:]]//g;
    my $nomFichierNettoye = $chemin . $nomFichierNettoyeBase;
    if ($nomFichierNettoye ne $nomFichier) {
      if ($force || (! fichierEnCoursDUtilisation($nomFichier))) {
        if (! $simule) {
          print "renomme $nomFichier en $nomFichierNettoye\n";
          my $nomFichierCorrige = prepareFichierPourShell($nomFichier);
          $nomFichierNettoye = prepareFichierPourShell($nomFichierNettoye);
          system("mv $nomFichierCorrige $nomFichierNettoye\n");
          # on met a jour nomFichier pour pouvoir recurrer
          $nomFichier = $nomFichierNettoye;
        } else {
          print "simulation : renommerait $nomFichier en $nomFichierNettoye\n";
        }
      } else {
        print "$nomFichier en cours d'utilisation : ne le renomme pas\n";
      }
    }
    # TODO: en cas de simulation, il faut récurrer dans nomFichier, sinon dans nomFichierNettoye
    # a faire et tester!
    # on recurre dans les dossiers, mais on ne suit pas les liens
    if ((-d $nomFichier) && (! -l $nomFichier)) {
      traiteDossier($nomFichier);
    }
  }
}


traiteDossier($dossier);

exit 0;
