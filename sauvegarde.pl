#!/usr/bin/perl

use Date::Parse;
use File::Basename;
use File::stat;
use Getopt::Long;
use POSIX;
use strict;
use Time::Local;


# force le flush sur STDOUT
select(STDOUT);
$| = 1;

my $dossierScript = dirname($0);
do "$dossierScript/utils.pl";

my $synchroJournal;
my $dossierDrapeaux;
my $dossierJournaux;


# ----- options de la ligne de commande -----
my $utilisation = "utilisation : $0 [-h] | -c fichierConfiguration [-t] [-f] [-v]";

my $texteAide = "Lance les sauvegardes automatiques
     -h | --help | -a | --aide : cette aide

     -c | --configuration : fichier de configuration avec la description des taches de sauvegardes a effectuer

     -t | --simule : simule le fonctionnement
     -f | --force : ne verifie pas le delai minimum depuis la derniere sauvegarde
     -v | --verbeux : ecrit plus d'informations sur le deroulement


Format du fichier de configuration:

  dossierRacine : dossierRacine : /Volumes/donnees/xavier/.sync

  # commentaire
  nom : xavier
  source : /Volumes/synology/xavier/xavier
  destination : /Volumes/donnees/sauvegardes\\ synology
  exclusion : temp
  supprimeDossiersSynology : oui
  corrigeNomsFichiers : oui
  ---

L'ordre des parametres n'a pas d'importance.
Une fois le dossier racine specifie, il n'est pas necessaire de repeter ce parametre.
On peut commenter une ligne en la faisant commencer par le caractere '#'.
La fin d'un bloc de parametres pour une sauvegarde doit se terminer par une ligne contenant trois tirets : \"---\".
Les espaces sont optionels (et on peut ajouter des espaces en debut et fin de ligne).
Les valeurs booleennes sont definies par oui (insensible a la casse) / n'importe quoi d'aute.\n";

Getopt::Long::Configure("bundling");
my ($aide, $fichierConfiguration, $force, $simule, $verbeux);
GetOptions(
           "aide|a|help|h" => \$aide,
           "configuration|c=s" => \$fichierConfiguration,
           "force|f" => \$force,
           "simule|t" => \$simule,
           "verbeux|v" => \$verbeux,
          ) or die $utilisation;

if ($aide) {
  print "$utilisation\n";
  print "$texteAide\n";
  exit 0;
}
die "$utilisation\n" if (! $fichierConfiguration);



# ----- synchronise -----
sub synchronise {
  my %args = (
              dossierSource => undef,
              dossierDestination => undef,
              dossierAExclure => undef,
              corrigeNomsFichiers => 0,
              supprimeDossiersSynology => 0,
              @_
             );
  my ($dossierSource, $dossierDestination, $dossierAExclure, $corrigeNomsFichiers, $supprimeDossiersSynology) = ($args{dossierSource}, $args{dossierDestination}, $args{dossierAExclure}, $args{corrigeNomsFichiers}, $args{supprimeDossiersSynology});

  ajouteAuFichier("", $synchroJournal) if (! $verbeux);

  # verifie l'existence des dossiers
  if (! -d $dossierSource) {
    print heureCourante() . " : ERREUR : dossier source $dossierSource non trouve !\n";
    return -1;
  }
  $dossierSource = prepareFichierPourShell($dossierSource);
  if (! -d $dossierDestination) {
    print heureCourante() . " : ERREUR : dossier cible $dossierDestination non trouve !\n";
    return -1;
  }
  $dossierDestination = prepareFichierPourShell($dossierDestination);

  # liste des dossiers a exclure
  my $clausesExclude = "";
  if (defined $dossierAExclure) {
    $clausesExclude .= " --exclude '$dossierAExclure'";
  }

  # efface les dossiers synology
  if ($supprimeDossiersSynology) {
    ajouteAuFichier(heureCourante() . " : efface les dossiers crees par Synology dans $dossierSource", $synchroJournal);
    my $commande = "find $dossierSource -name \"\@eaDir\" -exec rm -rf {} 2>/dev/null \\;";
    if (! $simule) {
      print "lance : $commande\n" if $verbeux;
      system($commande);
    }
    else {
      print "simulation : lancerait : $commande\n";
    }
  }

  # corrige les noms de fichiers avec accents
  if ($corrigeNomsFichiers) {
    ajouteAuFichier(heureCourante() . " : corrige les noms de fichiers avec accents", $synchroJournal);
    my $commande = "$dossierScript/corrigeNomsFichiers.pl -d $dossierSource";
    $commande .= " -f" if ($force);
    $commande .= " -s" if ($simule);
    $commande .= " | grep -v '^\$' >> $synchroJournal";
    print "lance : $commande\n" if $verbeux;
    system("$commande");
  }

  # rsync
  ajouteAuFichier(heureCourante() . " : lance la synchronisation des fichiers", $synchroJournal);
  my $commande = "rsync --omit-dir-times -vrlt --del $clausesExclude $dossierSource $dossierDestination | grep -v '^\$' >> $synchroJournal";
  if (! $simule) {
    print "lance : $commande\n" if $verbeux;
    system($commande);
  }
  else {
    print "simulation : lancerait : $commande\n";
  }

  return 0;
}



# ----- synchroniseSiNecessaire -----
sub synchroniseSiNecessaire {
  my %args = (
              dossierRacine => undef,
              nomTache => undef,
              dossierSource => undef,
              dossierDestination => undef,
              dossierAExclure => undef,
              corrigeNomsFichiers => 0,
              supprimeDossiersSynology => 0,
              @_
             );
  my ($dossierRacine, $nomTache, $dossierSource, $dossierDestination, $dossierAExclure, $corrigeNomsFichiers, $supprimeDossiersSynology) = ($args{dossierRacine}, $args{nomTache}, $args{dossierSource}, $args{dossierDestination}, $args{dossierAExclure}, $args{corrigeNomsFichiers}, $args{supprimeDossiersSynology});

  print "tache de synchronisation : $dossierRacine, $nomTache, $dossierSource, $dossierDestination, $dossierAExclure, $corrigeNomsFichiers, $supprimeDossiersSynology\n" if $verbeux;

  # verifie les dossiers
  if ((! -d "$dossierDrapeaux") || (! -W "$dossierDrapeaux")) {
    print "Probleme avec le repertoire $dossierDrapeaux\n";
    return;
  }
  if ((! -d "$dossierJournaux") || (! -W "$dossierJournaux")) {
    print "Probleme avec le repertoire $dossierJournaux\n";
    return;
  }

  # fichiers drapeaux
  my $synchroEnCours = "$dossierDrapeaux/${nomTache}SynchroEnCours";
  my $synchroFaite = "$dossierDrapeaux/${nomTache}SynchroFaite";

  # fichier journal
  $synchroJournal = "$dossierJournaux/${nomTache}SynchroJournal_" . strftime("%Y-%m", localtime()) . ".txt";

  ajouteAuFichier("\n" . heureCourante() . " : synchronise $dossierSource -> $dossierDestination", $synchroJournal) if $verbeux;

  # teste si une synchronisation est deja en cours
  if (-e $synchroEnCours) {
    my $heureSynchroEnCours = stat($synchroEnCours)->mtime;
    my $difference = time - $heureSynchroEnCours;
    my $message = heureCourante() . " : $dossierSource -> $dossierDestination : synchronisation en cours depuis " . strftime('%d/%m/%Y %H:%M:%S', localtime($heureSynchroEnCours))
      . ", soit il y a " . formatteDuree($difference);
    if ($difference > 6*60*60) {
      # force la synchronisation si le fichier drapeau a plus de 6 heures
      $message .= " : efface le fichier $synchroEnCours, et lance la synchronisation.\n";
      print $message;
      system("rm -f $synchroEnCours");
      # A FAIRE : tuer les anciens processus
    }
    else {
      $message .= " : passe la synchronisation\n";
      print $message;
      return -2;
    }
  }
  system("touch $synchroEnCours");

  my $passeSynchronisation = 0;
  # teste si la derniere synchronisation a ete faite il y a plus de 24 heures
  if (! $force) {
    if (-e $synchroFaite) {
      my $derniereHeureSynchro = stat($synchroFaite)->mtime;
      my $message = "Derniere synchronisation faite le " . strftime('%d/%m/%Y %H:%M:%S', localtime($derniereHeureSynchro));
      my $difference = time - $derniereHeureSynchro;
      $message .= ", soit il y a " . formatteDuree($difference) . ".";
      ajouteAuFichier($message, $synchroJournal) if $verbeux;
      if ($difference < 24*60*60) {
        $passeSynchronisation = 1;
      }
    }
    else {
      ajouteAuFichier("Pas de trace d'une synchronisation precedente.", $synchroJournal);
    }
  }

  if (! $passeSynchronisation) {
    print heureCourante() . " : synchronise  " . sprintf("%-36s", $dossierSource) . "  ->  $dossierDestination\n";
    synchronise(dossierSource => $dossierSource, dossierDestination => $dossierDestination, dossierAExclure => $dossierAExclure, corrigeNomsFichiers => $corrigeNomsFichiers, supprimeDossiersSynology => $supprimeDossiersSynology);
    if (! $simule) {
      system("touch $synchroFaite");
    }
    ajouteAuFichier(heureCourante() . " : synchronisation $dossierSource -> $dossierDestination faite", $synchroJournal);
  }

  # flag
  system("rm -f $synchroEnCours");
}



# --- main ---

# lit le fichier de configuration
die "Fichier de configuration $fichierConfiguration introuvable !\n" if (! -e $fichierConfiguration);
die "Fichier de configuration $fichierConfiguration non lisible !\n" if ((! -f $fichierConfiguration) || (! -r $fichierConfiguration));
die "Fichier de configuration $fichierConfiguration vide !\n" if (-z $fichierConfiguration);

open(FICHIER_CONFIGURATION, "<$fichierConfiguration") or die "Impossible de lire le fichier de configuration $fichierConfiguration !\n";

my %parametres = ();
my $dossierRacine = "";

while (<FICHIER_CONFIGURATION>) {
  chomp;
  next if ($_ eq "");
  next if ($_ =~ /^\s*#/);

  if ($_ =~ /\s*(\w*)\s*:\s*(.*)/) {
    my $parametre = $1;
    my $valeur = $2;
    $valeur =~ s/\s*$//;
    if ($parametre eq "dossierRacine") {
      $dossierRacine = $valeur;

      # cree et verifie les dossiers
      $dossierDrapeaux = "$dossierRacine/drapeaux";
      system("mkdir -p $dossierDrapeaux");
      $dossierJournaux = "$dossierRacine/journaux";
      system("mkdir -p $dossierJournaux");

      # redirige la sortie standard vers le fichier journal
      open(STDOUT, ">>$dossierJournaux/_sauvegardesJournal.txt");
      # redirige la sortie erreur sur la sortie standard
      open(STDERR, ">&STDOUT");
    }
    $parametres{$parametre} = $valeur;
  }

  elsif ($_ =~ /---/) {
    # fin de bloc de parametres
    # verifie la presence des parametres obligatoires
    if (! $parametres{nom}) {
      print heureCourante() . " : pas de nom pour la tache :\n";
      for (keys %parametres) {
        print heureCourante() . " : $_ = '$parametres{$_}'\n";
      }
    }
    elsif (! $parametres{source}) {
      print heureCourante() . " : pas de source pour la tache $parametres{nom}\n";
    }
    elsif (! $parametres{destination}) {
      print heureCourante() . " : pas de destination pour la tache $parametres{nom}\n";
    }

    else {
      # tous les parametres obligatoires sont presents
      # transforme les parametres booleens
      my $corrigeNomsFichiers = 0;
      if (lc($parametres{corrigeNomsFichiers}) eq "oui") {
        $corrigeNomsFichiers = 1;
      }
      my $supprimeDossiersSynology = 0;
      if (lc($parametres{supprimeDossiersSynology}) eq "oui") {
        $supprimeDossiersSynology = 1;
      }

      # lance la synchronisation, en testant le delai depuis la derniere synchronisation
      synchroniseSiNecessaire(dossierRacine => $dossierRacine,
                              nomTache => $parametres{nom},
                              dossierSource => $parametres{source},
                              dossierDestination => $parametres{destination},
                              dossierAExclure => $parametres{exclusion},
                              corrigeNomsFichiers => $corrigeNomsFichiers,
                              supprimeDossiersSynology => $supprimeDossiersSynology);
    }

    undef %parametres;
  }
}
close(FICHIER_CONFIGURATION);

exit 0;
