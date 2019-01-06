#!/usr/bin/env python3

import os
import sys
import re

from config import Config


def get_aligned_line_indices(initial_path, aligned_path):
    """Get index list of aligned lines from initial files.

    :param str initial_path: a path of the initial (.snt) file
    :param str aligned_path: a path of the aligned (.snt.aligned) file
    :return: a line index list
    :rtype: list
    """
    aligned_line_indices = list()

    with open(initial_path, encoding='utf-8') as initial, \
            open(aligned_path, encoding='utf-8') as aligned:
        initial_lines = initial.readlines()
        aligned_lines = aligned.readlines()

        last_aligned_idx = 0

        for aligned_line in aligned_lines:
            cur_idx = last_aligned_idx

            try:
                while cur_idx <= len(initial_lines):
                    cur_idx += 1
                    aligned_line = get_space_normalized_segment(aligned_line)
                    initial_line = get_space_normalized_segment(initial_lines[cur_idx - 1])

                    if aligned_line == initial_line:
                        aligned_line_indices.append(cur_idx)
                        last_aligned_idx = cur_idx
                        break
            except IndexError:
                aligned_line_indices.append(-1)

    return aligned_line_indices


def get_space_normalized_segment(segment):
    """Remove leading/trailing as well as multiple spaces from a string.

    :param str segment: a segment (sentence)
    :return: a string with no leading/trailing spaces and only containing single whitespaces
    :rtype: str
    """
    return re.sub(r'\s{2,}', ' ', segment).strip()


def write_parallel_index_files(cfg):
    lang_pair = '{}-{}'.format(cfg['source_language'], cfg['target_language'])
    lang_pair_work_directory = os.path.join(cfg['work_directory'], lang_pair)
    lang_pair_alignment_index_directory = os.path.join(cfg['alignment_index_directory'], lang_pair)

    if not os.path.exists(lang_pair_alignment_index_directory):
        os.makedirs(lang_pair_alignment_index_directory)

    for entry in os.scandir(lang_pair_work_directory):
        if entry.is_file() and entry.name.endswith('_{}.snt.aligned'.format(cfg['source_language'])):
            pair_title = entry.name.rsplit('.', 2)[0].rsplit('_', 1)[0]

            trg_path = os.path.join(lang_pair_work_directory,
                                    '{}_{}.snt.aligned'.format(pair_title, cfg['target_language']))

            if not os.path.exists(trg_path):
                continue

            aligned_docs = [entry.path,
                            trg_path]

            idx_docs = [os.path.join(lang_pair_alignment_index_directory,
                                     '{}.{}.idx'.format(pair_title, cfg['source_language'])),
                        os.path.join(lang_pair_alignment_index_directory,
                                     '{}.{}.idx'.format(pair_title, cfg['target_language']))]

            orig_docs = [os.path.join(os.path.join(cfg['source_data_directory'], 'snt'),
                                      '{}_{}.snt'.format(pair_title, cfg['source_language'])),
                         os.path.join(os.path.join(cfg['source_data_directory'], 'snt'),
                                      '{}_{}.snt'.format(pair_title, cfg['target_language']))]

            for i in range(len(aligned_docs)):
                indices = get_aligned_line_indices(orig_docs[i], aligned_docs[i])
                with open(idx_docs[i], 'w', newline='\n') as idx:
                    idx.write('\n'.join([str(n) for n in indices]) + '\n')


def main(config_path='io_args.yml'):
    try:
        cfg = Config(config_path).load()
        write_parallel_index_files(cfg)
    except Exception as ex:
        sys.stderr.write(repr(ex))
        return 1


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:]))
