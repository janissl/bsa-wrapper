#!/usr/bin/env python3

import os
import sys

from config import Config


def get_row_index_list(path):
    return [int(idx.strip()) for idx in open(path) if idx.strip()]


def get_segment_list(path):
    return [segment for segment in open(path, encoding='utf-8')]


def do_build(cfg):
    lang_pair = '{}-{}'.format(cfg['source_language'], cfg['target_language'])
    lang_pair_alignment_index_directory = os.path.join(cfg['alignment_index_directory'], lang_pair)

    if not os.path.exists(cfg['output_data_directory']):
        os.makedirs(cfg['output_data_directory'])

    out_path_base = os.path.join(cfg['output_data_directory'], '{}.{}'.format(cfg['corpus_title'], lang_pair))
    src_corpus_path = '{}.{}'.format(out_path_base, cfg['source_language'])
    trg_corpus_path = '{}.{}'.format(out_path_base, cfg['target_language'])

    with open(src_corpus_path, 'w', encoding='utf-8', newline='\n') as src,\
            open(trg_corpus_path, 'w', encoding='utf-8', newline='\n') as trg:
        src_idx_suffix = '.{}.idx'.format(cfg['source_language'])
        trg_idx_suffix = '.{}.idx'.format(cfg['target_language'])

        for entry in os.scandir(lang_pair_alignment_index_directory):
            if not (entry.is_file() and entry.name.endswith(src_idx_suffix)):
                continue

            pair_title = entry.name.rsplit('.', 2)[0]
            trg_idx_path = os.path.join(os.path.dirname(entry.path), '{}{}'.format(pair_title, trg_idx_suffix))

            if not os.path.exists(trg_idx_path):
                continue

            orig_src_path = os.path.join(os.path.join(cfg['original_source_data_directory'], 'snt'),
                                         '{}_{}.snt'.format(pair_title, cfg['source_language']))
            orig_trg_path = os.path.join(os.path.join(cfg['original_source_data_directory'], 'snt'),
                                         '{}_{}.snt'.format(pair_title, cfg['target_language']))

            src_segments = get_segment_list(orig_src_path)
            trg_segments = get_segment_list(orig_trg_path)

            src_idx_list = get_row_index_list(entry.path)
            trg_idx_list = get_row_index_list(trg_idx_path)

            for src_idx, trg_idx in zip(src_idx_list, trg_idx_list):
                if not (src_idx > 0 and trg_idx > 0):
                    continue

                try:
                    src.write(src_segments[src_idx - 1])
                    trg.write(trg_segments[trg_idx - 1])
                except IndexError:
                    sys.stderr.write('Pair: {}, source index: {}, target index: {}\n'.format(pair_title, src_idx, trg_idx))


def main(config_path='io_args.yml'):
    try:
        cfg = Config(config_path).load()
        do_build(cfg)
    except Exception as ex:
        sys.stderr.write(repr(ex))
        return 1


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:]))
