function value = isImportedResults(results)
% Excel から読み込んだ結果か（alignest.importResults は imported に読んだファイルを入れる）
value = isstruct(results) && isfield(results, "imported") && strlength(results.imported) > 0;
end
