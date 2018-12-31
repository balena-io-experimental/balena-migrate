extern crate yaml_rust;
use yaml_rust::{YamlLoader, Yaml}; //  YamlEmitter,
// use std::io;
use std::io::Read;
use std::env;
use std::fs::File;
use std::error::Error;
use std::process;
use std::fmt;
use std::process::Command;
use std::str;
use ::std::fs;

type BoxResult<T> = Result<T,Box<Error>>;



#[derive(Debug)]
struct ParseError {
    details: String
}

impl ParseError {
    fn new(msg: &str) -> ParseError {
        ParseError{details: msg.to_string()}
    }
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f,"{}",self.details)
    }
}

impl Error for ParseError {
    fn description(&self) -> &str {
        &self.details
    }
}

fn parse_config (file_name : &String) -> BoxResult<Vec<Yaml>> {
    let mut f = File::open(file_name)?;
    let mut content = String::new();
    f.read_to_string(&mut content)?;
    // println!("With text:\n{}", content);
    let config = YamlLoader::load_from_str(&content)?;
    return Ok(config);
}

fn map_files (vol_name: &str, source: &str, target: &str, filter: &str ) -> BoxResult<bool> {
    // TODO: map files into temp dir
    return Ok(true)
}


fn evaluate_config (file_name: &String ) -> BoxResult<bool> {
    let config = parse_config(file_name)?;

    println!("got {} configs", config.len());

    if config.len() == 0  {
        return Err(Box::new(ParseError::new("Encountered an empty configuration - no backup file created")));
    }

    if config.len() > 1 {
        eprintln!("WARNING: Encountered more than on top level item, ignoring all but the first");
    }

    let cfg = &config[0];

    if !cfg.is_array() {
        return Err(Box::new(ParseError::new("Expected an array of volumes at top level")));
    }

    // Debug support
    // println!("{:?}", cfg);


    for volume in cfg.as_vec().unwrap() {
        let vol_name = volume["volume"].as_str().expect("volume is not a string");
        let vol_content= &volume["contents"];
        if vol_content.is_badvalue() {
            return Err(Box::new(ParseError::new(&format!("Encountered missing items parameter in volume {}", vol_name))));
        }

        if !vol_content.is_array() {
            return Err(Box::new(ParseError::new(&format!("contents does not appear to be an array in volume {}", vol_name))));
        }

        println!("processing volume: {}", vol_name);
        let mut idx = 0;
        for item in vol_content.as_vec().unwrap() {
            // println!("item [{}] {:?}", idx, item);
            let source = &item["source"];
            if source.is_badvalue() {
                return Err(Box::new(ParseError::new(&format!("volume[{}].contents[{}] missing parameter source", vol_name, idx))));
            }

            let source =  match source.as_str() {
                Some(str) => str,
                None => return Err(Box::new(ParseError::new(&format!("volume[{}].contents[{}] parameter source is not a string", vol_name, idx))))
            };
            println!("  using source: {}", source);

            let target = &item["target"];
            let target = if target.is_badvalue() { "" } else {
                match target.as_str() {
                    Some(str) => str,
                    None => return Err(Box::new(ParseError::new(&format!("volume[{}].contents[{}] parameter target is not a string", vol_name, idx))))
                }
            };
            println!("  - with target: {}", target);

            let filter = &item["filter"];
            let filter = if filter.is_badvalue() { "" } else {
                match filter.as_str() {
                    Some(str) => str,
                    None => return Err(Box::new(ParseError::new(&format!("volume[{}].contents[{}] parameter filter is not a string", vol_name, idx))))
                }
            };
            println!("  - with filter: {}", filter);


            map_files(vol_name, source, target, filter);

            idx = idx + 1;

        }
    }
    return Ok(true);
}

fn main () {
    let args: Vec<String> = env::args().collect();

    if args.len() < 3 {
        panic!("Please provide backup target file and backup definition file as command line parameters");
    }

    let backup_file = &args[1];
    let def_file = &args[2];

    println!("Input:  {}", def_file);
    println!("Output: {}", backup_file);

    let output= Command::new("sh")
        .arg("-c")
        .arg("mktemp -d -p ./")
        .output()
        .expect("failed to create temporary directory");

    let tmp_dir = str::from_utf8(&output.stdout).expect("unable to read commad output").trim();
    println!("Temporary directory: '{}'", tmp_dir);


    match evaluate_config(def_file) {
        Ok(_res) => {
            eprintln!("success");
        },
        Err(e) => {
            eprintln!("{:?}",e);
        }
    };
    fs::remove_dir_all(tmp_dir).expect("failed to remove temporary directory");

}
