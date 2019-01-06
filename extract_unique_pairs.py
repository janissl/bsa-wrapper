#!/usr/bin/env python3
"""Extract unique segment pairs from parallel corpora."""

import os
import sys
import hashlib

from config import Config


def get_paired_segment_hash(s_string, t_string):
    segment_hash = hashlib.sha256('{}\t{}'.format(s_string, t_string).encode()).hexdigest()
    empty_values_hash = hashlib.sha256('\t'.encode()).hexdigest()

    return segment_hash if segment_hash != empty_values_hash else ''


def write_unique_file_pair(cfg):
    lang_pair = '{}-{}'.format(cfg['source_language'], cfg['target_language'])
    path_base = os.path.join(cfg['output_data_directory'], cfg['corpus_title'])

    all_source_path = '{}.{}.{}'.format(path_base, lang_pair, cfg['source_language'])
    all_target_path = '{}.{}.{}'.format(path_base, lang_pair, cfg['target_language'])

    unique_source_path = '{}.unique.{}.{}'.format(path_base, lang_pair, cfg['source_language'])
    unique_target_path = '{}.unique.{}.{}'.format(path_base, lang_pair, cfg['target_language'])

    if os.path.exists(all_source_path) and \
            os.path.exists(all_target_path) and \
            os.stat(all_source_path).st_size and \
            os.stat(all_target_path).st_size:
        with open(all_source_path, encoding='utf-8') as s_in, \
                open(all_target_path, encoding='utf-8') as t_in, \
                open(unique_source_path, 'w', encoding='utf-8', newline='\n') as s_out, \
                open(unique_target_path, 'w', encoding='utf-8', newline='\n') as t_out:
            unique_segments = dict()

            for s_line, t_line in zip(s_in, t_in):
                segment_hash = get_paired_segment_hash(s_line.strip(), t_line.strip())

                if not segment_hash:
                    continue

                try:
                    unique_segments[segment_hash] += 1
                except KeyError:
                    unique_segments[segment_hash] = 1
                    s_out.write(s_line)
                    t_out.write(t_line)


def main(config_path='io_args.yml'):
    try:
        cfg = Config(config_path).load()
        write_unique_file_pair(cfg)
    except Exception as ex:
        sys.stderr.write(repr(ex))
        return 1


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:]))
