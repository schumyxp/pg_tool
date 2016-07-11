<?php
class pg_count{

	function __construct($src=0, $ipt=0){
		$this->source_count = $src;
		$this->input_count = $ipt;
	}
	
	public $source_count = 0;
	public $input_count = 0;
	
	public function total_count(){
		return $source_count + $input_count;
	}
};

$source = array();

$i=0;
$all_words =[];
$input_allline=[];
//read input
$inputfile = fopen($argv[2], "r");
while(!feof($inputfile)){
    $line = fgets($inputfile);
    $input_allline[] = $line;
    $row = array_unique(explode(" ", $line));
    
    //record all the words
    foreach($row as $word){
    	$t = fixWord($word);
    	if( isset($all_words[$t]) ){
    		$all_words[$t]->input_count++;
    		continue;
    	}
    	else{
    		$all_words[$t] = new pg_count(0,1);
    	}
    }
    $i++;
}
fclose($inputfile);
echo "read $i lines from input\n";

//read source
$i = 0;
$sourcefile = fopen($argv[1], "r");
while(!feof($sourcefile)){
    $line = fgets($sourcefile);
    $arr = explode(" ", $line);
    foreach($arr as $word)
    {
    	$t = fixWord($word);
    	$source[$t] = 1;
    	
    	if( isset($all_words[$t]) ){
    		$all_words[$t]->source_count++;
    	}
    	else{
    		$all_words[$t] = new pg_count(1,0);
    	}
    }
    $arr = [];
    $i++;
}
fclose($sourcefile);
echo "read $i lines from source\n\n";


//var_dump($input_words);
//check duplicated
$input = array();
echo "checking duplicated:\n";
foreach($input_allline as $oneline){
	$should_keep = false;
    $words = array_unique(explode(" ", $oneline));
	foreach($words as $word){
		$t = fixWord($word);
		//not in source and not duplicated in input
		if($all_words[$t]->source_count < 1 &&
			$all_words[$t]->input_count <= 1){
			$should_keep = true;
			break;
		}
	}
	if($should_keep){
		$input[] = trim($oneline);
	}
	else{
		foreach($words as $word){
			$t = fixWord($word);
			if($all_words[$t]->input_count > 1){
				$all_words[$t]->input_count--;
			}
		}
		echo trim($oneline)." duplicated in source or input\n";
	}
}


/*
echo "start checking...\n";
//check
$result = array();
for($i=0; $i < count($input); $i++){
	$row = explode(" ", $input[$i]);
	foreach($row as $word){
		$t = fixWord($word);
		if ( $source[$t] > 0 ){
			echo "$t existed in source\n";
		}
		else{
			$result[] = trim(implode(' ', $row));
			break;
		}
	}
}
*/

echo "\nresult=======>:\n";
//show result:
for($i=0; $i < count($input); $i++){
	echo $input[$i]."\n";
}


function fixWord($word){
	$t = strtolower(trim($word));
    $t = str_replace("(", "", $t);
    $t = str_replace(")", "", $t);
	return $t;
}