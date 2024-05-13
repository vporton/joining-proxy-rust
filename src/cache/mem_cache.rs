use std::{collections::HashMap, time::{Duration, SystemTime}};
use std::collections::BTreeMap;

use crate::{cache::cache::Cache, errors::MyResult};

use super::cache::{Key, Value};

pub struct MemCache {
    data: HashMap<Vec<u8>, Vec<u8>>,
    put_times: BTreeMap<SystemTime, Vec<u8>>, // time -> key
}

impl MemCache {
    pub fn new() -> Self {
        Self {
            data: HashMap::new(),
            put_times: BTreeMap::new(), // FIXME: In theory, multiple items may have the same time.
        }
    }
}

impl Cache for MemCache {
    fn put(&mut self, key: Key, value: Value, _save_for: Duration) -> MyResult<()> {
        self.data.insert(Vec::from(key.0), Vec::from(value.0));
        self.put_times.insert(SystemTime::now(), Vec::from(key.0));

        Ok(())
    }

    fn get(&mut self, key: Key, save_for: Duration) -> MyResult<Option<&Vec<u8>>> {
        // Remove expired entries.
        let time = SystemTime::now();
        while let Some(kv) = self.put_times.first_key_value() {
            if *kv.0 < time - save_for {
                self.data.remove(kv.1);
                self.put_times.pop_first();
            }
        }

        Ok(self.data.get(&Vec::from(key.0))) // TODO: inefficient?
    }
}