@echo off

set config_file=io_args.yml

echo 1. Aligning sentences...
python do_segment_alignment.py %config_file% || goto ERR

echo 2. Finding aligned sentence indices in the original segmented files...
python get_segment_alignments.py %config_file% || goto ERR

echo 3. Building parallel corpora...
python build_parallel_corpora.py %config_file% || goto ERR

echo 4. Extract unique segment pairs...
python extract_unique_pairs.py %config_file% || goto ERR

echo Done.
exit /b

:ERR
echo.
echo ERROR: Process aborted!
exit /b 1
