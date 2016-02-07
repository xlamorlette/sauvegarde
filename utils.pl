use POSIX;
use strict;
use Time::Local;

# --- heureCourante ---
# retourne l'heure courante dans un format lisible
sub heureCourante {
  strftime('%d/%m/%Y %H:%M:%S', localtime());
}

# --- formatteDuree ---
# formatte la duree donnee en secondes dans un format lisible
sub formatteDuree {
  my $resultat = "";
  my $jours = int($_[0]/(24*60*60));
  if ($jours > 0) {
    $resultat .= "${jours}j ";
  }
  my $heures = ($_[0]/(60*60))%24;
  if (($heures > 0) || ($resultat != "")) {
    $resultat .= "${heures}h";
  }
  my $minutes = ($_[0]/60)%60;
  if (($minutes > 0) || ($resultat != "")) {
    $resultat .= "${minutes}'";
  }
  my $secondes = $_[0]%60;
  $resultat .= "${secondes}\"";
}

# --- ajouteAuFichier ---
# $_[0] : texte a ajouter
# $_[1] : nom du fichier
sub ajouteAuFichier {
  my ($texte, $nomFichierJournal) = @_;
  $texte =~ s/\"/\\"/g;
  system("echo \"$texte\" >> $nomFichierJournal");
}

# --- echoTee ---
# affiche le texte sur la sortie standard, et l'ajoute au fichier donne
# $_[0] : texte a ajouter
# $_[1] : nom du fichier
sub echoTee {
  my ($texte, $nomFichier) = @_;
  $texte =~ s/\"/\\"/g;
  system("echo \"$texte\" | tee -a $nomFichier");
}

# --- systemTee ---
# execute la commande et copie sa sortie sur la sortie standard, et l'ajoute au fichier donne
# $_[0] : commande a executer
# $_[1] : nom du fichier
sub systemTee {
  system("$_[0] | tee -a $_[1]");
}

# --- prepareFichierPourShell ---
sub prepareFichierPourShell {
  my ($nomFichier) = @_;
  $nomFichier =~ s/ /\\ /g;
  $nomFichier =~ s/\(/\\\(/g;
  $nomFichier =~ s/\)/\\\)/g;
  $nomFichier =~ s/&/\\&/g;
  $nomFichier =~ s/'/\\'/g;
  $nomFichier =~ s/"/\\"/g;
  $nomFichier;
}
