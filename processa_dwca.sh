#!/bin/bash
###################################################################################################################################################
#Autoria: Raul Sena Ferreira em 18/07/2014
#Local do Script: Dentro da pasta do usuário jboss
#Parâmetros: 2 parâmetros, ((parâmetro 1) == 0) -> importação via arquivo, caso contrário, link de importação, (parametro 2) é a url/arquivo a ser mexido.
#OBS: -Trabalha em conjunto com os arquivos sql responsáveis por pegar os dados extraídos e salvar no banco (); -É necessário o uso do .pgpass na pasta de usuário do sistema; -É necessário instalação do cpanm Spreadsheet::ParseExcel Spreadsheet::XLSX;
###################################################################################################################################################

tipoProcesso=$1
arquivo=$2
dwca=COLOQUE O NOME DO SEU ARQUIVO SQL RESPONSÁVEL PELA ROTINA DE SALVAR NO BANCO OS OCCURRENCES E OS IDENTIFICATIONS
dwca_occurrence=COLOQUE O NOME DO SEU ARQUIVO SQL RESPONSÁVEL PELA ROTINA DE SALVAR NO BANCO OS OCCURRENCES
dwca_identification=COLOQUE O NOME DO SEU ARQUIVO SQL RESPONSÁVEL PELA ROTINA DE SALVAR NO BANCO OS IDENTIFICATIONS
HOST=COLOQUE O SEU HOST AQUI
usuario=COLOQUE O USUARIO DO SEU BANCO AQUI
bancoDeDados=NOME DO SEU BANCO DE DADOS AQUI
DEST="/tmp"
DWCA=dwca.txt
EXT=.txt
occur=occurrence
ident=identification
data=$(date +"%Y-%m-%d-%H-%M-%S")
pathDWCA="dwca-$data"
extensaoArquivo=${arquivo##*.}
flagImportacao=""

function processaXML(){
	(/usr/bin/tr -d $'\r' < $1) | ./xmlparser
        mv 'identification.txt' $DEST/$pathDWCA/'identification_dwca.txt'
	mv 'occurrence.txt' $DEST/$pathDWCA/'occurrence_dwca.txt'
}

function processaDWCA() {
	# verificando se é necessário mudar o encoding do arquivo pra UTF-8
	if [ "$2" != "UTF-8" ] && [ "$2" != "utf-8" ] && [ "$2" != "UTF8" ] && [ "$2" != "utf8" ];
	then
		echo "Transformando $2 para utf-8"
		/usr/bin/iconv -f $2 -t UTF8 $1'.txt' > $1'saida.txt'
		#troca \ por \\
		sed 's:\\:\\\\:g' $1'saida.txt' > $1'.txt'
		echo "Conversão realizada"
	else
		echo "Não transformou arquivo em UTF8"
	fi
	# se estiver separado por "," então chama o parser(processa)
	if [ "$3" == "," ]
	then
		#troca \ por \\
		sed 's:\\:\\\\:g' $1'.txt' > $1'saida.txt'
		./processa < $1'saida.txt' > $1'_dwca.txt'
		echo "Script processa (lex) iniciado"
	else
		sed 's:\\:\\\\:g' $1'.txt' > $1'_dwca.txt'
		echo "Separador de campo diferente de vírgula"
	fi
}

function executaSQL() {
	if [ "$1" == "$occur$ident" ] ;then
		env PGOPTIONS='-c client_min_messages=WARNING' /usr/bin/psql -h $HOST -d $bancoDeDados -U $usuario -f $dwca
	fi
	if [ "$1" == "$occur" ]; then
		env PGOPTIONS='-c client_min_messages=WARNING' /usr/bin/psql -h $HOST -d $bancoDeDados -U $usuario -f $dwca_occurrence
	fi
	if [ "$1" == "$ident" ]; then
		env PGOPTIONS='-c client_min_messages=WARNING' /usr/bin/psql -h $HOST -d $bancoDeDados -U $usuario -f $dwca_identification
	fi
}

function converteExcel2Csv(){
	# Procuro o nome do arquivo e mudo seu nome, para depois convertê-lo para txt e usá-lo na importação
	mv $DEST/"$arquivo" $DEST/$pathDWCA/planilha_dwca"$1"
	
	soffice --headless --convert-to csv $DEST/$pathDWCA/planilha_dwca"$1"
	mv planilha_dwca.csv $DEST/$pathDWCA/occurrence.txt
	/usr/bin/iconv -f iso-8859-1 -t utf8 $DEST/$pathDWCA/occurrence.txt > $DEST/$pathDWCA/'saida.txt'
	#troca \ por \\
	sed 's:\\:\\\\:g' $DEST/$pathDWCA/'saida.txt' > $DEST/$pathDWCA/occurrence.txt		
	
	./processa < $DEST/$pathDWCA/occurrence.txt > $DEST/$pathDWCA/occurrence_dwca.txt
}

## Main
/bin/mkdir $DEST/$pathDWCA
cp -a $dwca_occurrence $DEST/$pathDWCA/$dwca_occurrence
cp -a $dwca_identification $DEST/$pathDWCA/$dwca_identification
cp -a $dwca $DEST/$pathDWCA/$dwca
cp -a processa $DEST/$pathDWCA/processa
cp -a xmlparser $DEST/$pathDWCA/xmlparser

# Se a entrada for um arquivo
if [ $tipoProcesso == "0" ]
then
	if [ $extensaoArquivo == "xlsx" ] #Se o arquivo for .xlsx
	then
		converteExcel2Csv ".xlsx"
		flagImportacao="$flagImportacao$occur"
	fi

	if [ $extensaoArquivo == "xls" ] #Se o arquivo for .xls
	then
		converteExcel2Csv ".xls"
		flagImportacao="$flagImportacao$occur"
	fi

	if [ $extensaoArquivo == "zip" ] # Se o arquivo for um zip, verifica ocorrencia de arquivos dwca em formato txt, xls ou xlsx, converte e sobe os mesmos para o servidor
	then
		mv $DEST/"$arquivo" $DEST/$pathDWCA/dwca.zip #descomentar na versão de produção 
		/usr/bin/unzip -j -o $DEST/$pathDWCA/dwca.zip -d $DEST/$pathDWCA >> /tmp/dwca_shell.log 2>&1

		if [ -e $DEST/$pathDWCA/meta.xml ]
		then
			tipoEncoding=`grep core  $DEST/$pathDWCA/meta.xml | grep -m 1 -Po 'encoding="\K.*?(?=")'`;
			separadorCampo=`grep -m 1 -Po 'fieldsTerminatedBy="\K.*?(?=")' $DEST/$pathDWCA/meta.xml`;
			
			if [ -e $DEST/$pathDWCA/occurrence.txt ]
			then
				processaDWCA $DEST/$pathDWCA/$occur $tipoEncoding $separadorCampo
				flagImportacao="$flagImportacao$occur"
			else
				echo "Nenhum arquivo occurrence encontrado." 
			fi

			if [ -e $DEST/$pathDWCA/identification.txt ]
			then
				processaDWCA $DEST/$pathDWCA/$ident $tipoEncoding $separadorCampo
				flagImportacao="$flagImportacao$ident"
			else
				echo "Nenhum arquivo identification encontrado." 
			fi
		fi

		if [ -e $DEST/$pathDWCA/*.xls ]
		then
			converteExcel2Csv ".xls"
			flagImportacao="$flagImportacao$occur"
		else
			echo " " 
		fi

		if [ -e $DEST/$pathDWCA/*.xlsx ]
		then
			converteExcel2Csv ".xlsx"
			flagImportacao="$flagImportacao$occur"
		else
			echo " " 
		fi
	fi

	if [ $extensaoArquivo == "xml" ] #Se o arquivo for .xml
	then
		mv $DEST/"$arquivo" $DEST/$pathDWCA/"$arquivo"
		processaXML $DEST/$pathDWCA/"$arquivo"
		flagImportacao="$flagImportacao$occur"
		flagImportacao="$flagImportacao$ident"
	else
		echo " "
	fi
fi
# Se a entrada for um link para um arquivo zip
if [ $tipoProcesso == "1" ]
then
	/usr/bin/wget -O $DEST/$pathDWCA/dwca.zip "$arquivo" >> /tmp/dwca_shell.log 2>&1
	/usr/bin/unzip -j -o $DEST/$pathDWCA/dwca.zip -d $DEST/$pathDWCA >> /tmp/dwca_shell.log 2>&1
	
	if [ -e $DEST/$pathDWCA/meta.xml ]
	then
		tipoEncoding=`grep -m 1 -Po 'encoding="\K.*?(?=")' $DEST/$pathDWCA/meta.xml`;
		separadorCampo=`grep -m 1 -Po 'fieldsTerminatedBy="\K.*?(?=")' $DEST/$pathDWCA/meta.xml`;
		
		if [ -e $DEST/$pathDWCA/occurrence.txt ]
		then
			processaDWCA $DEST/$pathDWCA/$occur $tipoEncoding $separadorCampo
			flagImportacao="$flagImportacao$occur"
		else
			echo "Nenhum arquivo occurrence encontrado." 
		fi

		if [ -e $DEST/$pathDWCA/identification.txt ]
		then
			processaDWCA $DEST/$pathDWCA/$ident $tipoEncoding $separadorCampo
			flagImportacao="$flagImportacao$ident"
		else
			echo "Nenhum arquivo identification encontrado." 
		fi
	fi

	if [ -e $DEST/$pathDWCA/*.xls ]
	then
		converteExcel2Csv ".xls"
		flagImportacao="$flagImportacao$occur"
	else
		echo " " 
	fi

	if [ -e $DEST/$pathDWCA/*.xlsx ]
	then
		converteExcel2Csv ".xlsx"
		flagImportacao="$flagImportacao$occur"
	else
		echo " " 
	fi

	if [ $extensaoArquivo == "xml" ] #Se o arquivo for .xml
	then
		mv $DEST/"$arquivo" $DEST/$pathDWCA/"$arquivo"
		processaXML $DEST/$pathDWCA/"$arquivo"
		flagImportacao="$flagImportacao$occur"
		flagImportacao="$flagImportacao$ident"
	else
		echo " "
	fi
fi

cd $DEST/$pathDWCA/
#conexao com o banco e execucao das queries
executaSQL $flagImportacao
/bin/rm -r $DEST/$pathDWCA/ #remove pasta dos arquivos já importados
exit
