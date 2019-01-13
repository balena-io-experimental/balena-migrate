extern crate regex;
extern crate yaml_rust;
use yaml_rust::{YamlLoader, Yaml};
use std::io::Read;
use std::env;
use std::fs::File;
use std::path::Path;
use std::fs::create_dir;
use std::fs::read_dir;
use std::fs::remove_dir_all;
use std::error::Error;
use std::fmt;
use std::process::Command;
use std::process::exit;
use std::str;
use std::os::unix::fs::symlink;
use regex::Regex;

type BoxResult<T> = Result<T,Box<Error>>;


// define custom error trait for parse errors

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

fn create_target_path (temp_dir: &str, vol_name: &str, target: &str) -> BoxResult<String> {
    let mut target_path: String = temp_dir.to_owned();    
    if ! target_path.ends_with("/") {
        target_path.push_str("/");
    }
    
    target_path.push_str(vol_name);

    if target.len() > 0 {
        if ! target_path.ends_with("/") {
            target_path.push_str("/");
        }

        target_path.push_str(target);
    }

    if target_path.ends_with("/") {
        target_path.pop();
    }

    if ! Path::new(&target_path).exists() {
        create_dir(&target_path)?;
    }

    if ! target_path.ends_with("/") {
        target_path.push_str("/");
    }

    return Ok(target_path);
}


fn map_files (temp_dir: &str, vol_name: &str, source: &str, target: &str, filter: &str ) -> BoxResult<bool> {
    // println!("  >> map_files: Volume: '{}', Source: '{}',  Target: '{}', Filter: '{}'", vol_name, source, target, filter);

    let mut source_str : String = source.to_string();

    if source_str.ends_with("/") {
        source_str.pop();
    }
    
    let source_path = Path::new(&source_str);

    if ! source_path.exists() {
        return Err(Box::new(ParseError::new(&format!("cannot access source '{}'",source_str))));
    }

    
    if filter != "" {
        if source_path.is_dir() {
            let target_path : String = create_target_path(temp_dir, vol_name, target)?;
            let re = Regex::new(filter).unwrap();

            for entry in read_dir(source_path)? {
                let entry = entry?;                

                // let mut curr_target: String = ;
                let fname = entry.file_name();                
                let fname = match  fname.to_str() {
                    Some(f) => f,
                    None => return Err(Box::new(ParseError::new(&format!("invalid file name '{:?}'", &fname))))
                };
                                
                let mut curr_target = target_path.to_owned();
                curr_target.push_str(&fname);
                let mut curr_src: String  = source_str.to_owned();
                if ! curr_src.ends_with("/") {
                    curr_src.push_str("/");
                }
                
                curr_src.push_str(&fname);
                
                if ! re.is_match(fname) {
                    println!("  skipping file: '{}'", &curr_src);
                } else {
                    println!("  linking '{}' to '{:?}'", &curr_src , &curr_target);
                    symlink(&curr_src , &curr_target)?;
                }
            }
            println!("");
        } else {
            return Err(Box::new(ParseError::new(&format!("Filter option cannot be applied to file {}", source_str))));
        }
    } else {
        if target.len() > 0 {
            let mut target_path = create_target_path(temp_dir, vol_name, "")?;
            target_path.push_str(target);            
            println!("  linking '{}' to '{}'\n", source_str, target_path);
            symlink(&source_str, target_path)?;
        } else {
            let mut target_path: String = temp_dir.to_owned();    
            if ! target_path.ends_with("/") {
                target_path.push_str("/");
            }            
            target_path.push_str(vol_name);
            if target_path.ends_with("/") {
                target_path.pop();
            }            
            println!("  linking '{}' to '{}'\n", source_str, target_path);
            symlink(&source_str, target_path)?;
        }
    }

    return Ok(true)
}


fn evaluate_config (file_name: &String, tmp_dir: &str ) -> BoxResult<()> {
    let config = parse_config(file_name)?;

    println!("Got {} configs", config.len());

    if config.len() == 0  {
        return Err(Box::new(ParseError::new("Encountered an empty configuration - no backup file created")));
    }

    if config.len() > 1 {
        eprintln!("WARNING: Found more than on top level item, ignoring all but the first");
    }

    let cfg = &config[0];

    if !cfg.is_array() {
        return Err(Box::new(ParseError::new("Expected an array of volumes at top level")));
    }

    // Debug support
    // println!("{:?}", cfg);


    for volume in cfg.as_vec().unwrap() {
        let vol_name = volume["volume"].as_str().expect("volume is not a string");
        let vol_content= &volume["content"];
        if vol_content.is_badvalue() {
            return Err(Box::new(ParseError::new(&format!("Encountered missing items parameter in volume {}", vol_name))));
        }

        if !vol_content.is_array() {
            return Err(Box::new(ParseError::new(&format!("content does not appear to be an array in volume {}", vol_name))));
        }

        println!("Processing volume: '{}'", vol_name);
        let mut idx = 0;
        for item in vol_content.as_vec().unwrap() {
            // println!("item [{}] {:?}", idx, item);
            let source = &item["source"];
            if source.is_badvalue() {
                return Err(Box::new(ParseError::new(&format!("volume[{}].content[{}] missing parameter source", vol_name, idx))));
            }

            let source =  match source.as_str() {
                Some(str) => str,
                None => return Err(Box::new(ParseError::new(&format!("volume[{}].content[{}] parameter source is not a string", vol_name, idx))))
            };
            println!("  using source: '{}'", source);

            let target = &item["target"];
            let target = if target.is_badvalue() { "" } else {
                match target.as_str() {
                    Some(str) => str,
                    None => return Err(Box::new(ParseError::new(&format!("volume[{}].content[{}] parameter target is not a string", vol_name, idx))))
                }
            };
            println!("  - with target: '{}'", target);

            let filter = &item["filter"];
            let filter = if filter.is_badvalue() { "" } else {
                match filter.as_str() {
                    Some(str) => str,
                    None => return Err(Box::new(ParseError::new(&format!("volume[{}].content[{}] parameter filter is not a string", vol_name, idx))))
                }
            };
            println!("  - with filter: '{}'", filter);


            match map_files(tmp_dir, vol_name, source, target, filter) {
                Ok(res) => res,
                Err(e) => return Err(e)
            };

            idx = idx + 1;

        }
    }
    return Ok(());
}

fn main () {
    let args: Vec<String> = env::args().collect();

    if args.len() < 3 {
        println!("Please provide backup target file and backup definition file as command line parameters\n");
        println!("Usage: data-migration <backup-file> <backup-def-file>\n");
        exit(1);
    }

    let backup_file = &args[1];
    let def_file = &args[2];

    println!("Using Definition File:  {}", def_file);
    println!("Using Output File: {}", backup_file);

    let output = Command::new("sh")
        .arg("-c")
        .arg("mktemp -d -p ./")
        .output()
        .expect("failed to create temporary directory");

    let tmp_dir = str::from_utf8(&output.stdout).expect("unable to read command output").trim();
    println!("Using Temporary directory: '{}'", tmp_dir);

    match evaluate_config(def_file,&tmp_dir) {
        Ok(()) => println!("Backup set up successfully"),
        Err(e) => {
            remove_dir_all(tmp_dir).expect("failed to remove temporary directory");
            panic!("Failed to parse defintion file '{}', error: {:?}",def_file, e);
        }
    };
    
    let cmd_str = &format!("tar -hzcf \"{}\" -C \"{}\" .", backup_file, tmp_dir);
    println!("Archiving with command string: '{}'", cmd_str);
    let _output = Command::new("sh")
        .arg("-c")
        .arg(cmd_str)
        .output()
        .expect("failed to create backup file");

    remove_dir_all(tmp_dir).expect("failed to remove temporary directory");

}
