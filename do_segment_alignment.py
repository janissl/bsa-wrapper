#!/usr/bin/env python3
"""A wrapper for sentence alignment in bilingual files."""

import os
import sys

import shutil
import subprocess

from config import Config


def get_perl_location_from_system_path():
    """Return a full path of the Perl interpreter.

        :return: a path of the perl.exe directory or None if that directory is not included in PATH
        :rtype: str
    """
    perl_location = None

    if os.name == 'nt':
        for path in os.environ['PATH'].split(os.pathsep):
            if path and os.path.exists(os.path.join(path, 'perl.exe')):
                perl_location = path
                break

        if perl_location is None:
            sys.stderr.write("Couldn't find a Perl interpreter on the current machine\n")

    return perl_location


def do_alignment(cfg):
    """Align sentences in bilingual files using Bilingual Sentence Aligner

    :param dict cfg: a dict object with configuration values loaded from a YAML file
    """
    lang_pair = '{}-{}'.format(cfg['source_language'], cfg['target_language'])
    lang_pair_work_directory = os.path.join(cfg['work_directory'], lang_pair)

    if os.path.exists(lang_pair_work_directory):
        shutil.rmtree(lang_pair_work_directory)

    os.makedirs(lang_pair_work_directory)

    aligner = os.path.join('bsa', 'align-sents-all-multi-file.pl')

    for entry in os.scandir(cfg['preprocessed_source_data_directory']):
        if not entry.name.endswith('_{}.snt'.format(cfg['source_language'])):
            continue

        target_filepath = '{}_{}.snt'.format(entry.path.rsplit('_', 1)[0], cfg['target_language'])

        if not os.path.exists(target_filepath):
            continue

        src_dest_path = os.path.join(lang_pair_work_directory, entry.name)
        trg_dest_path = os.path.join(lang_pair_work_directory, os.path.basename(target_filepath))
        shutil.copyfile(entry.path, src_dest_path)
        shutil.copyfile(target_filepath, trg_dest_path)

    alignment_log_filepath = os.path.join(cfg['work_directory'], '{}_sent_align.log'.format(lang_pair))
    cmd_args = list()

    if os.name == 'nt':
        cmd_args.append('perl')

    cmd_args.extend([aligner, lang_pair_work_directory, cfg['source_language'], cfg['target_language']])

    with open(alignment_log_filepath, 'w', encoding='utf-8', newline='\n') as log_file:
        subprocess.run(cmd_args, stdout=log_file, stderr=log_file)


def main(config_path='io_args.yml'):
    """Align sentences in parallel files.

    :param str config_path: a path of a project configuration file
    """
    perl_location = get_perl_location_from_system_path()

    if os.name == 'nt' and perl_location is None:
        return 1

    try:
        cfg = Config(config_path).load()
        do_alignment(cfg)
    except Exception as ex:
        sys.stderr.write(repr(ex))
        return 1


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:]))
