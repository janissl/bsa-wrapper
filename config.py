#!/usr/bin/env python3

import yaml


class Config:
    def __init__(self, path):
        self.path = path

    def load(self):
        with open(self.path, encoding='utf-8') as cfg_file:
            cfg_str = cfg_file.read()

        cfg = yaml.load(cfg_str)

        return cfg
